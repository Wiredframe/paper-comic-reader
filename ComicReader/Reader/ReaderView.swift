//
//  ReaderView.swift
//  Comic Reader
//
//  The reading experience: a full-bleed paged, zoomable view. Tap toggles the
//  chrome (top: close + page counter; bottom: bookmark, page grid, bookmarks).
//  Resumes on the last read page, saves progress, and records the open time so
//  the book surfaces in Recents.
//

import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// A request to open a comic, optionally at a specific page (e.g. from a bookmark).
struct ReaderTarget: Identifiable {
    let id = UUID()
    let book: ComicBook
    var page: Int?
    /// The `matchedTransitionSource` id the zoom presentation should grow out of. The Library
    /// and Recents decks grow the reader from the *cover* (so this stays nil and they pass
    /// `book.id`); the Bookmarks deck grows it from the *bookmarked page*, whose card is keyed by
    /// the bookmark's id — different from the book's — so it sets this explicitly. A nil (or
    /// unmatched) id simply falls back to the standard slide-up.
    var sourceID: UUID?
}

struct ReaderView: View {
    let book: ComicBook
    /// Page to open on (e.g. a bookmark jump); falls back to the resume page.
    var initialPage: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PaperSettings.self) private var paper
    @Environment(ReaderSettings.self) private var settings
    @Environment(DownloadManager.self) private var downloads
    // The reader is a fullScreenCover; `.preferredColorScheme` set on the tab view does
    // not reach it, so it reads the appearance itself to keep the reader background and
    // any presented sheets in the chosen theme.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
    @Environment(\.colorScheme) private var systemScheme

    /// Effective dark/light for the reader. Named colors (assets) don't resolve reliably
    /// inside a fullScreenCover, so the background is computed from this directly.
    private var readerIsDark: Bool {
        switch AppAppearance.from(appearanceRaw) {
        case .dark:   return true
        case .light:  return false
        case .system: return systemScheme == .dark
        }
    }

    /// Letterbox behind the page: a neutral grey so the page edges read without the glare
    /// of white (light) or the harshness of black (dark) — a bright mat in light mode, a
    /// deep one in dark mode. When the paper effect is on, the grey is warmed toward the
    /// page's cream tone, tracking the effect's own *warmth* setting (0 = neutral grey,
    /// 1 = full cream) so the mat always matches how warm the pages actually look; with the
    /// effect off it stays neutral. The UIKit collection view draws the actual letterbox, so
    /// the same colour is handed to it (see `ReaderHost`); the SwiftUI copy backs the loading state.
    private var readerBackground: Color { Color(readerBackgroundUIColor) }
    private var readerBackgroundUIColor: UIColor {
        // Warmth follows the paper effect: its warmth slider (0…1) while enabled, else neutral.
        let warmth = paper.isEnabled ? max(0, min(1, paper.params.warmth)) : 0
        let neutral, warm: (r: CGFloat, g: CGFloat, b: CGFloat)
        if readerIsDark {
            neutral = (0.16, 0.16, 0.17); warm = (0.20, 0.17, 0.13)   // deep mat → warm amber
        } else {
            neutral = (0.64, 0.64, 0.65); warm = (0.68, 0.64, 0.55)   // bright mat → warm cream
        }
        return UIColor(red:   neutral.r + (warm.r - neutral.r) * warmth,
                       green: neutral.g + (warm.g - neutral.g) * warmth,
                       blue:  neutral.b + (warm.b - neutral.b) * warmth,
                       alpha: 1)
    }

    @State private var store: PageImageStore?
    @State private var currentPage = 0
    @State private var chromeVisible = true
    /// Pending auto-hide of the chrome (armed on show, cancelled on manual hide / rotation /
    /// leaving the reader / an open sheet). Nil when nothing is scheduled.
    @State private var autoHideTask: Task<Void, Never>?
    @State private var paperVersion = 0
    @State private var jumpTarget: Int?
    @State private var showGrid = false
    @State private var bookmarkTick = 0   // nudges the view when bookmarks change
    @State private var bookmarkingPages: Set<Int> = []   // pages with an add in flight — guards double-taps
    /// One open = one count. @State is per-presentation, which is exactly the semantics
    /// wanted — see `setup()`.
    @State private var didCountOpen = false
    /// Guards the one-shot archive open, which `store` can no longer do itself now that it
    /// arrives asynchronously — see `setup()`.
    @State private var didStartOpen = false
    /// Whether the reader is currently sideways, measured rather than inferred from the size
    /// class (which is regular in both orientations on iPad). Gates the drag-down dismiss —
    /// see `body`.
    @State private var isLandscape = false
    /// True while a page is pinch-zoomed. Disables the interactive drag-down dismiss so a
    /// downward pan across the zoomed page pans the page instead of dismissing the reader.
    @State private var isZoomed = false
    /// The reader is holding the interface sideways, because the landscape button in the bottom
    /// bar was tapped. Per presentation on purpose: it is an act on the comic in front of you,
    /// not a preference, so the next comic starts on the device orientation again. Held through
    /// a trip to another app and back, which is what `OrientationGate.holdLandscape` is for.
    @State private var holdsLandscape = false

    // MARK: Folder-backed fetch (only used when this comic's bytes aren't local)
    //
    // The single funnel: every way into the reader lands here, so materialising a folder-backed
    // comic's archive on demand is done once, in `ensureLocalThenOpen`, rather than at each call
    // site. The fetch itself belongs to `DownloadManager`, and the reader only watches it: opening
    // a comic the library is already fetching joins that download instead of starting a second
    // one, and leaving the reader mid-fetch no longer throws the megabytes away.

    /// True while the archive is being fetched from the library folder — shows the download state
    /// instead of the plain open spinner.
    @State private var isDownloading = false
    /// Set when the fetch fails, which raises the resolve dialog (update folder path / choose a
    /// file / cancel). Nil the rest of the time. Stays set until the source is really sorted out,
    /// so the reader can't be left waiting on a picker that came back empty (see `ComicResolve`).
    @State private var resolveRequest: ComicResolveRequest?
    /// The fetch was stopped rather than failed (from here or from the library), so the reader
    /// waits on nothing and offers to start it again.
    @State private var didStopFetch = false

    private var pageCount: Int { store?.pageCount ?? book.pageCount }
    private var isBookmarked: Bool {
        _ = bookmarkTick
        return book.bookmarks.contains { $0.pageIndex == currentPage }
    }

    var body: some View {
        ZStack {
            readerBackground.ignoresSafeArea()

            if let store, store.pageCount > 0 {
                ReaderHost(store: store,
                           settings: settings,
                           // Threaded in as a plain value (not just the `$settings.doublePage`
                           // binding in the menu) so `body` actually READS it: under fine-grained
                           // @Observable tracking that read is what re-renders here and drives
                           // updateUIViewController → syncLayoutMode when the toggle flips.
                           doublePage: settings.doublePage,
                           startIndex: clampedStart(store.pageCount),
                           currentPage: $currentPage,
                           paperVersion: paperVersion,
                           jumpTarget: $jumpTarget,
                           backgroundColor: readerBackgroundUIColor,
                           onToggleChrome: toggleChrome,
                           onReachedEnd: markRead,
                           onZoomActiveChanged: { isZoomed = $0 })
                    .ignoresSafeArea()
            } else if store != nil {
                // Archive couldn't be opened (missing / corrupt after import).
                ReaderUnavailableView()
            } else if resolveRequest != nil {
                // Fetch failed — the resolve dialog below drives the choice; this is what sits
                // behind it (and what remains if the user dismisses without choosing), with the
                // way back in, since the dialog can be dismissed by tapping outside it.
                ReaderNotDownloadedView(onRetry: retryFetch)
            } else if isDownloading {
                ReaderDownloadingView(book: book) { downloads.cancel(book.id) }
            } else if didStopFetch {
                // The download was stopped, here or from the library. Same state as a failed
                // fetch minus the explanation: there's nothing wrong, it just isn't here.
                ReaderNotDownloadedView(onRetry: retryFetch)
            } else {
                ProgressView().tint(.secondary)   // reads on both the dark and the light letterbox mat
            }

            // Keep the chrome in the hierarchy always (fade via opacity) so the
            // SwiftUI layout is identical whether it's shown or hidden — otherwise
            // removing it changes how the hosted reader is laid out mid-rotation
            // and the resize drops out of the animation (janky rotation). The fade is
            // applied per Liquid-Glass island inside `chrome` (each `.glassEffect`
            // carries its own `.opacity(chromeVisible …)`), NOT here as one group
            // opacity over the whole VStack: a group `.opacity` whose subtree holds
            // backdrop-filter (glass) views forces the render server to re-blur the
            // full-screen backdrop into an offscreen buffer on every frame of the
            // fade, which dropped frames as the chrome faded. Per-island alpha animates
            // each small glass layer against a cached backdrop instead.
            chrome
                .allowsHitTesting(chromeVisible)
        }
        .statusBarHidden(!chromeVisible)
        .preferredColorScheme(AppAppearance.from(appearanceRaw).colorScheme)
        // No drag-down dismiss while sideways. The zoom would have to land back on a cover
        // that only exists in portrait, and the rotation can't be got out of the way first the
        // way the Close button does it (`close()`) — an interactive dismiss is already under
        // way by the time anyone could ask. Close and the manual portrait toggle still work.
        .interactiveDismissDisabled(isLandscape || isZoomed)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { nowLandscape in
            guard nowLandscape != isLandscape else { return }   // a real portrait/landscape flip
            isLandscape = nowLandscape
            // Orientation change: clear the controls at once (no fade) so the glass never has to
            // blur the page grain through the rotation, and the reflow is seen unobstructed.
            var noAnim = Transaction()
            noAnim.disablesAnimations = true
            withTransaction(noAnim) { chromeVisible = false }
            cancelAutoHide()
        }
        .task { await setup() }
        .onDisappear {
            cancelAutoHide()
            persistProgress()   // durable checkpoint on leaving the reader
            // Guaranteed portrait reset on close — a fallback for the controller's
            // viewWillDisappear (which doesn't always fire for a fullScreenCover), so a
            // forced landscape never lingers after leaving the reader.
            OrientationGate.lockPortrait()
        }
        // Save the resume page when the app leaves the foreground (progress only needs to
        // survive backgrounding / closing, not every page turn — see persistProgress).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                persistProgress()
            }
        }
        .onChange(of: paper.isEnabled) { reloadPaper() }
        .onChange(of: paper.params) { reloadPaper() }
        .onChange(of: showGrid) { _, isOpen in
            // Pause the auto-hide while the page grid is up; resume it when the grid closes.
            if isOpen { cancelAutoHide() } else if chromeVisible { armAutoHide() }
        }
        .sheet(isPresented: $showGrid) {
            if let store {
                PageGridView(store: store, pageCount: store.pageCount, current: currentPage) { page in
                    // Persist the jump here (a clean user event) and update the counter.
                    // The scroll itself is driven by jumpTarget inside updateUIViewController,
                    // where a state change wouldn't reliably fire onChange.
                    currentPage = page
                    persistProgress()
                    jumpTarget = page
                    showGrid = false
                }
                // A default sheet is a narrow centred card on iPad — too skinny for a page grid.
                // `.page` sizes it to near full-screen there so the thumbnails get the width;
                // no effect on a phone, where sheets are already edge-to-edge.
                .presentationSizing(.page)
            }
        }
        // A folder-backed comic that wouldn't fetch. Shared with the library, which can now start
        // the same download and hit the same wall (see `ComicResolve`). Resolving it here means
        // trying this comic again; cancelling means there is nothing to read, so the reader goes.
        .comicResolve($resolveRequest, onResolved: { _ in retryFetch() }, onCancel: close)
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            if hasPages { bottomBar }
        }
        // Standard label colour so the chrome icons are dark on light and white on dark,
        // matching the system reading apps. The buttons sit on Liquid Glass.
        .foregroundStyle(.primary)
    }

    /// False once an archive fails to open (pageCount 0) — the page counter and the reading
    /// controls have nothing to act on, so the chrome shows just the Close button.
    private var hasPages: Bool { pageCount > 0 }

    private var topBar: some View {
        HStack {
            circleButton("xmark", label: "Close", action: close)
            Spacer()
            if hasPages {
                Text("\(currentPage + 1) / \(pageCount)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .glassEffect(in: Capsule())
                    .opacity(chromeVisible ? 1 : 0)   // per-island fade — see `chrome`
                    .accessibilityLabel("Page \(currentPage + 1) of \(pageCount)")
            }
            Spacer()
            if hasPages { settingsMenu }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Top-right overlay: the GLOBAL reader toggles (paper effect + double page),
    /// changed right here with the page as a live preview.
    private var settingsMenu: some View {
        @Bindable var paper = paper
        @Bindable var settings = settings
        return Menu {
            Toggle(isOn: $paper.isEnabled) {
                Label("Paper Effect", systemImage: "doc.plaintext")
            }
            Toggle(isOn: $settings.doublePage) {
                Label("Double Page", systemImage: "book.pages")
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
                .frame(width: 44, height: 44)   // ≥ 44pt touch target
                .glassEffect(in: Circle())
                .opacity(chromeVisible ? 1 : 0)   // per-island fade — see `chrome`
        }
        .accessibilityLabel("Reader settings")
    }

    private var bottomBar: some View {
        HStack(spacing: 26) {
            barButton(isBookmarked ? "bookmark.fill" : "bookmark",
                      label: isBookmarked ? "Remove bookmark" : "Add bookmark",
                      tint: isBookmarked ? .accentColor : .primary) {
                toggleBookmark()
            }
            barButton("square.grid.2x2", label: "Page grid") { showGrid = true }
            barButton("rectangle.landscape.rotate",
                      label: holdsLandscape ? "Follow device orientation" : "Read in landscape",
                      tint: holdsLandscape ? .accentColor : .primary) {
                toggleLandscapeHold()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 13)
        .glassEffect(in: Capsule())
        .opacity(chromeVisible ? 1 : 0)   // per-island fade — see `chrome`
        .padding(.bottom, 10)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 44, height: 44)   // ≥ 44pt touch target
                .glassEffect(in: Circle())
                .opacity(chromeVisible ? 1 : 0)   // per-island fade — see `chrome`
        }
        .accessibilityLabel(label)
    }

    private func barButton(_ icon: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)   // ≥ 44pt touch target
        }
        .accessibilityLabel(label)
    }

    // MARK: Chrome visibility

    /// Reveal the chrome, then auto-hide it after a short idle (matching the system reading
    /// apps). The auto-hide is cancelled by a manual hide, an orientation change, an open sheet,
    /// or leaving the reader; see `armAutoHide`.
    private func showChrome() {
        withAnimation(.easeInOut(duration: settings.uiAnimationDuration)) { chromeVisible = true }
        armAutoHide()
    }

    /// Hide the chrome now, cancelling any pending auto-hide.
    private func hideChrome() {
        cancelAutoHide()
        withAnimation(.easeInOut(duration: settings.uiAnimationDuration)) { chromeVisible = false }
    }

    private func toggleChrome() { chromeVisible ? hideChrome() : showChrome() }

    /// Schedule the chrome to fade away after a 2-second idle. Re-arming (another tap) restarts
    /// the clock; an open sheet holds it off until the sheet closes. Uses a cancellable Task so
    /// the fade rides Core Animation on the render server, never a main-thread timer loop.
    private func armAutoHide() {
        cancelAutoHide()
        guard !showGrid else { return }
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hideChrome()
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    /// Closes the reader, rotating back to portrait FIRST when sideways.
    ///
    /// The mask is app-wide and permissive while the reader is up, so everything behind it is
    /// laid out in landscape too — just covered. Dismissing straight away reveals the library
    /// sideways for the moment it takes the rotation to land, which reads as a bug. Rotating
    /// while the reader still covers the screen means there's nothing sideways to see.
    private func close() {
        persistProgress()
        guard OrientationGate.isLandscape else {
            OrientationGate.lockPortrait()
            dismiss()
            return
        }
        OrientationGate.lockPortrait()
        DispatchQueue.main.asyncAfter(deadline: .now() + OrientationGate.settleDuration) {
            dismiss()
        }
    }

    /// Turns the reader sideways and keeps it there, or hands it back to the device.
    ///
    /// The reader is the only thing on screen when this runs, so the rotation is the system's
    /// own animation over the page and the spread morph that already rides it (see
    /// `ReaderCollectionController.viewWillTransition`). Nothing else in the app is visible to
    /// rotate with it, which is the reason this lives here rather than being decided before the
    /// reader is presented.
    ///
    /// Under the device rotation lock this is the only way to reach the double-page spread at
    /// all: iOS will not turn the interface on its own, so it has to be asked.
    private func toggleLandscapeHold() {
        holdsLandscape.toggle()
        if holdsLandscape { OrientationGate.holdLandscape() } else { OrientationGate.free() }
        // The chrome is cleared by the geometry change that follows (see `body`), so there is
        // deliberately no fade to arrange here.
    }

    // MARK: Actions

    /// Opens the archive, then settles the reader on it.
    ///
    /// The open runs OFF the main actor (`PageImageStore.open`) and everything that needs a real
    /// page count waits for it. It used to happen right here, synchronously: opening is file I/O
    /// that scales with the archive rather than the page, so a big comic — or any comic whose
    /// bytes were cold — froze the whole app until it finished, and the loading state below could
    /// never even draw. Now the spinner shows and the app stays live while it opens.
    ///
    /// Orientation is deliberately not touched here: the reader controller handles it in
    /// viewWillAppear/viewWillDisappear (standard UIKit lifecycle) so the rotation rides the
    /// present/dismiss transition instead of flashing afterwards.
    private func setup() async {
        // `store` stays nil for as long as the open takes, so it can't stand in as the guard
        // the way it did when it was assigned synchronously — a second appear would start a
        // second open on top of the first.
        guard !didStartOpen else { return }
        didStartOpen = true

        // The import-time page count came off this same archive, so the counter and the resume
        // page are already right while it opens; the store's own count replaces it below in
        // case the file changed underneath us since.
        currentPage = clampedStart(book.pageCount)

        await ensureLocalThenOpen()
    }

    /// Fetches the archive first when this is a folder-backed comic without local bytes, then
    /// opens it. On a fetch failure it raises the resolve dialog and stops; whatever answers that
    /// dialog comes back through `retryFetch`.
    ///
    /// The presence check is the file system, not `book.hasLocalArchive`: the flag drives the
    /// library badge but can drift (a purged file), and the reader must act on what's actually
    /// on disk. When they disagree, the flag is reconciled below.
    private func ensureLocalThenOpen() async {
        if book.isFolderBacked, !Storage.fm.fileExists(atPath: book.archiveURL.path) {
            guard book.sourceRelativePath != nil else {
                presentResolve(.notConfigured); return
            }
            isDownloading = true
            do {
                // The fetch belongs to `DownloadManager`, not to this view: it may already be
                // running (started from a listing), and it carries on if the reader goes away.
                try await downloads.join(book, in: context)
                isDownloading = false
            } catch let error as LibrarySource.SourceError {
                isDownloading = false
                // Cancelled from here or from a listing: nothing to resolve, just stop.
                if case .cancelled = error { didStopFetch = true; return }
                presentResolve(error)
                return
            } catch is CancellationError {
                isDownloading = false
                didStopFetch = true
                return
            } catch {
                isDownloading = false
                presentResolve(.copyFailed)
                return
            }
        }
        // The reader may have been dismissed while the bytes were coming in. The download
        // outlives it; this open must not.
        guard !Task.isCancelled else { return }
        await openStore()
    }

    /// Try this comic again after the source was sorted out, or after a cancelled download.
    /// Its own task: whatever raised this (the resolve dialog, a button) is not the `.task`
    /// that owns the open.
    private func retryFetch() {
        resolveRequest = nil
        didStopFetch = false
        Task { await ensureLocalThenOpen() }
    }

    /// Opens the (now-local) archive and settles the reader on it. The open runs OFF the main
    /// actor (`PageImageStore.open`); everything that needs a real page count waits for it.
    private func openStore() async {
        let opened = await PageImageStore.open(bookID: book.id, url: book.archiveURL,
                                               paperEnabled: paper.isEnabled, paperParams: paper.params)
        store = opened
        currentPage = clampedStart(opened.pageCount)
        // First reveal auto-hides after the idle too, same as a tap-triggered reveal, but only
        // once there are pages to read (a failed open keeps the Close button up).
        if opened.pageCount > 0 { armAutoHide() }

        // Auto-mark read when opening already on the last page — `.onChange(of: currentPage)`
        // only fires on a change, so a 1-page comic (or resuming on the final page) would
        // otherwise never be marked read despite reaching the end. Guard on pageCount so a
        // comic whose archive failed to open (pageCount 0) isn't marked read.
        if opened.pageCount > 0, currentPage >= opened.pageCount - 1 { markRead() }
        // Count the open once per presentation, riding the save below. openStore() is written to
        // be re-runnable (re-setting a date is idempotent) — incrementing a counter is not,
        // and a double count would be silent and permanent. Guarded on pageCount like
        // markRead above, so a comic whose archive won't open can't gain popularity.
        if opened.pageCount > 0, !didCountOpen {
            didCountOpen = true
            book.openCount += 1
        }
        book.dateOpened = .now
        try? context.save()
    }

    // MARK: Resolve a missing source

    /// Take the failure over from the download manager: whoever is in front explains it, and the
    /// library behind must not raise a second dialog about the same comic.
    private func presentResolve(_ error: LibrarySource.SourceError) {
        downloads.clearFailure(for: book.id)
        resolveRequest = ComicResolveRequest(book: book, error: error)
    }

    private func clampedStart(_ count: Int) -> Int {
        let base = initialPage ?? book.lastReadPage
        return min(max(base, 0), max(count - 1, 0))
    }

    /// Writes the resume page at durable checkpoints (close, backgrounding, a page-grid
    /// jump) rather than on every page turn: a per-turn `save()` republishes the library
    /// @Query (which re-sorts in its body), and reading progress only needs to survive
    /// leaving the reader.
    private func persistProgress() {
        guard book.lastReadPage != currentPage else { return }
        book.lastReadPage = currentPage
        try? context.save()
    }

    /// Mark the comic read once the last page is reached. Never un-marks automatically —
    /// that stays a manual choice in the cover menu. Bookmarks are untouched.
    private func markRead() {
        guard !book.isRead else { return }
        book.isRead = true
        try? context.save()
    }

    private func reloadPaper() {
        store?.setPaper(enabled: paper.isEnabled, params: paper.params)
        paperVersion += 1
    }

    private func toggleBookmark() {
        if let existing = book.bookmarks.first(where: { $0.pageIndex == currentPage }) {
            try? Storage.fm.removeItem(at: existing.thumbURL)
            context.delete(existing)
            try? context.save()
            bookmarkTick += 1
        } else {
            let page = currentPage
            // Adding is async (a thumbnail decode) and isBookmarked stays false until it
            // commits, so a second tap in that window would insert a duplicate bookmark for
            // the same page. Guard the page until this add resolves.
            guard !bookmarkingPages.contains(page) else { return }
            bookmarkingPages.insert(page)
            // Bookmark cards render at the same full-width size as covers, so match
            // the cover resolution rather than a small thumbnail.
            Task { @MainActor in
                defer { bookmarkingPages.remove(page) }
                guard let image = await store?.thumbnail(at: page, maxPixel: ImageDownsampler.libraryCardPixel) else { return }
                let name = "\(UUID().uuidString).jpg"
                ImageDownsampler.writeJPEG(image, to: Storage.bookmarkThumbURL(name))
                // The page's shape, free — the carousel needs it to size an uncropped card, and
                // the decoded image is right here. Older bookmarks get it backfilled from the
                // thumbnail's header instead.
                let aspect: Double? = image.size.height > 0
                    ? Double(image.size.width / image.size.height) : nil
                context.insert(Bookmark(pageIndex: page, thumbName: name,
                                        pageAspect: aspect, book: book))
                try? context.save()
                bookmarkTick += 1
            }
        }
    }
}

/// Shown when a comic's archive can't be opened — moved, deleted, or corrupted after import.
/// Reachable via the reader's Close button in the chrome above.
private struct ReaderUnavailableView: View {
    var body: some View {
        ContentUnavailableView(
            "Couldn't open this comic",
            systemImage: "exclamationmark.triangle",
            description: Text("The file may have been moved, or is no longer a readable CBZ archive.")
        )
    }
}

/// Shown while a folder-backed comic's archive is being fetched from the library folder: the
/// same ring the library shows, at a size worth tapping, with the stop mark in the middle.
///
/// A leaf that looks the download up itself, so the megabyte-by-megabyte progress re-renders
/// this and nothing else.
private struct ReaderDownloadingView: View {
    let book: ComicBook
    let onCancel: () -> Void

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(spacing: 14) {
            Button(action: onCancel) {
                // Grey rather than accent: it sits alone on the letterbox mat, where the accent
                // would shout, and the rest of the loading state is grey too. One ring for the
                // whole fetch — it turns while the copy is still working out how big this is,
                // then fills (see `DownloadRing`).
                DownloadRing(progress: downloads.ticket(for: book.id)?.progress ?? 0,
                             size: 56, glyph: "stop.fill", tint: .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop downloading")

            Text("Downloading from your library…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Sits behind the resolve dialog when a folder-backed comic won't fetch, and remains if the
/// user dismisses the dialog without choosing. It carries the way back in, since a dialog
/// dismissed by tapping outside would otherwise leave the Close button as the only move.
private struct ReaderNotDownloadedView: View {
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Not downloaded", systemImage: "icloud.slash")
        } description: {
            Text("This comic isn’t on your device yet.")
        } actions: {
            Button("Download", action: onRetry).buttonStyle(.borderedProminent)
        }
    }
}

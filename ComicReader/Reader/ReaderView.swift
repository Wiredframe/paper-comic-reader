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
    @EnvironmentObject private var paper: PaperSettings
    @EnvironmentObject private var settings: ReaderSettings
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
    @State private var paperVersion = 0
    @State private var jumpTarget: Int?
    @State private var showGrid = false
    @State private var bookmarkTick = 0   // nudges the view when bookmarks change
    @State private var bookmarkingPages: Set<Int> = []   // pages with an add in flight — guards double-taps
    @State private var autoHide: DispatchWorkItem?
    /// One open = one count. @State is per-presentation, which is exactly the semantics
    /// wanted — see `setup()`.
    @State private var didCountOpen = false
    /// Guards the one-shot archive open, which `store` can no longer do itself now that it
    /// arrives asynchronously — see `setup()`.
    @State private var didStartOpen = false
    /// Manual landscape override — session-only, not persisted. Toggling it also returns
    /// to portrait, so it's a plain landscape⇄portrait switch for rotation-locked devices.
    @State private var forcedLandscape = false
    /// Whether the reader is currently sideways, measured rather than inferred from the size
    /// class (which is regular in both orientations on iPad). Gates the drag-down dismiss —
    /// see `body`.
    @State private var isLandscape = false

    // MARK: Folder-backed fetch (only used when this comic's bytes aren't local)
    //
    // The single funnel: every way into the reader lands here, so materialising a folder-backed
    // comic's archive on demand is done once, in `ensureLocalThenOpen`, rather than at each call site.

    /// True while the archive is being fetched from the library folder — shows the download state
    /// instead of the plain open spinner.
    @State private var isDownloading = false
    /// Set when the fetch fails, which raises the resolve dialog (update folder path / choose a
    /// file / cancel). Nil the rest of the time.
    @State private var resolveError: LibrarySource.SourceError?
    @State private var showFolderPicker = false
    @State private var showFilePicker = false

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
                           startIndex: clampedStart(store.pageCount),
                           currentPage: $currentPage,
                           paperVersion: paperVersion,
                           jumpTarget: $jumpTarget,
                           backgroundColor: readerBackgroundUIColor,
                           onToggleChrome: toggleChrome,
                           onReachedEnd: markRead)
                    .ignoresSafeArea()
            } else if store != nil {
                // Archive couldn't be opened (missing / corrupt after import).
                ReaderUnavailableView()
            } else if resolveError != nil {
                // Fetch failed — the resolve dialog below drives the choice; this is what sits
                // behind it (and what remains if the user dismisses without choosing).
                ReaderNotDownloadedView()
            } else if isDownloading {
                ReaderDownloadingView()
            } else {
                ProgressView().tint(.secondary)   // reads on both the dark and the light letterbox mat
            }

            // Keep the chrome in the hierarchy always (fade via opacity) so the
            // SwiftUI layout is identical whether it's shown or hidden — otherwise
            // removing it changes how the hosted reader is laid out mid-rotation
            // and the resize drops out of the animation (janky rotation).
            chrome
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
        }
        .statusBarHidden(!chromeVisible)
        .preferredColorScheme(AppAppearance.from(appearanceRaw).colorScheme)
        // No drag-down dismiss while sideways. The zoom would have to land back on a cover
        // that only exists in portrait, and the rotation can't be got out of the way first the
        // way the Close button does it (`close()`) — an interactive dismiss is already under
        // way by the time anyone could ask. Close and the manual portrait toggle still work.
        .interactiveDismissDisabled(isLandscape)
        .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: { isLandscape = $0 }
        .task { await setup() }
        .onDisappear {
            autoHide?.cancel()
            persistProgress()   // durable checkpoint on leaving the reader
            // Guaranteed portrait reset on close — a fallback for the controller's
            // viewWillDisappear (which doesn't always fire for a fullScreenCover), so a
            // forced landscape never lingers after leaving the reader.
            OrientationGate.lockPortrait()
        }
        // Save the resume page when the app leaves the foreground (progress only needs to
        // survive backgrounding / closing, not every page turn — see persistProgress).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistProgress() }
        }
        .onChange(of: paper.isEnabled) { reloadPaper() }
        .onChange(of: paper.params) { reloadPaper() }
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
        // A folder-backed comic that wouldn't fetch. The failure is deliberately surfaced only
        // here, on open — never a background sweep. The three choices cover both real causes
        // without guessing between them: the whole folder moved (update its path, which re-links
        // every entry at once), or just this file did (pick it directly), or the share is simply
        // offline right now (cancel and come back on the right network).
        .confirmationDialog("Couldn’t load this comic",
                            isPresented: Binding(get: { resolveError != nil },
                                                 set: { if !$0 { resolveError = nil } }),
                            titleVisibility: .visible) {
            Button("Update Folder Path…") { showFolderPicker = true }
            Button("Choose Another File…") { showFilePicker = true }
            Button("Cancel", role: .cancel) { close() }
        } message: {
            Text(resolveMessage)
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            handleFolderPicked(result)
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: ComicUTType.all) { result in
            handleReplacementPicked(result)
        }
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
        Menu {
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
            barButton(forcedLandscape ? "rotate.left" : "rotate.right",
                      label: forcedLandscape ? "Return to portrait" : "Rotate to landscape",
                      tint: forcedLandscape ? .accentColor : .primary) {
                toggleLandscape()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 13)
        .glassEffect(in: Capsule())
        .padding(.bottom, 10)
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 44, height: 44)   // ≥ 44pt touch target
                .glassEffect(in: Circle())
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

    /// Reveal the chrome and (re)arm the auto-hide. Rotation no longer depends on this
    /// — the reader re-fits the page inside the turn itself (see viewWillTransition).
    private func showChrome() {
        withAnimation(.easeInOut(duration: settings.uiAnimationDuration)) { chromeVisible = true }
        scheduleAutoHide()
    }

    /// Hide the chrome now and cancel any pending auto-hide.
    private func hideChrome() {
        autoHide?.cancel()
        autoHide = nil
        withAnimation(.easeInOut(duration: settings.uiAnimationDuration)) { chromeVisible = false }
    }

    private func toggleChrome() { chromeVisible ? hideChrome() : showChrome() }

    /// Closes the reader, rotating back to portrait FIRST when sideways.
    ///
    /// The mask is app-wide and permissive while the reader is up, so everything behind it is
    /// laid out in landscape too — just covered. Dismissing straight away reveals the library
    /// sideways for the moment it takes the rotation to land, which reads as a bug. Rotating
    /// while the reader still covers the screen means there's nothing sideways to see.
    private func close() {
        persistProgress()
        autoHide?.cancel()
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

    /// Fade the chrome out after a short idle so the controls never linger. Re-armed
    /// every time it's shown (tap, first open, rotation).
    private func scheduleAutoHide() {
        autoHide?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: settings.uiAnimationDuration)) { chromeVisible = false }
        }
        autoHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
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
    /// opens it. On a fetch failure it raises the resolve dialog and stops — the retry paths
    /// (`handleFolderPicked` / `handleReplacementPicked`) call back in here.
    ///
    /// The presence check is the file system, not `book.hasLocalArchive`: the flag drives the
    /// library badge but can drift (a purged file), and the reader must act on what's actually
    /// on disk. When they disagree, the flag is reconciled below.
    private func ensureLocalThenOpen() async {
        if book.isFolderBacked, !Storage.fm.fileExists(atPath: book.archiveURL.path) {
            guard let relativePath = book.sourceRelativePath else {
                presentResolve(.notConfigured); return
            }
            let dest = book.archiveURL
            isDownloading = true
            do {
                try await Importer.downloadArchive(relativePath: relativePath, into: dest) { _ in }
                isDownloading = false
                book.hasLocalArchive = true
                try? context.save()
            } catch let error as LibrarySource.SourceError {
                isDownloading = false
                // Closing the reader mid-fetch cancels the task — nothing to resolve, just leave.
                if case .cancelled = error { return }
                presentResolve(error)
                return
            } catch {
                isDownloading = false
                presentResolve(.copyFailed)
                return
            }
        }
        await openStore()
    }

    /// Opens the (now-local) archive and settles the reader on it. The open runs OFF the main
    /// actor (`PageImageStore.open`); everything that needs a real page count waits for it.
    private func openStore() async {
        let opened = await PageImageStore.open(bookID: book.id, url: book.archiveURL,
                                               paperEnabled: paper.isEnabled, paperParams: paper.params)
        store = opened
        currentPage = clampedStart(opened.pageCount)

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
        // The chrome starts visible, then fades. Armed only once there's a page to look at, so
        // a slow open doesn't spend the delay on the spinner — and never when the archive
        // wouldn't open, since Close is then the only way out and it must not fade away.
        if opened.pageCount > 0 { scheduleAutoHide() }
    }

    // MARK: Resolve a missing source

    private func presentResolve(_ error: LibrarySource.SourceError) {
        resolveError = error
    }

    /// The reason text for the resolve dialog, tuned to the failure but never over-committing:
    /// "file missing" and "folder offline" look identical from here, so each message keeps the
    /// "or the server is offline" door open rather than pushing the user to re-pick needlessly.
    private var resolveMessage: String {
        switch resolveError {
        case .notConfigured:
            return "This comic comes from a library folder that isn’t set up on this device. Choose the folder, or pick this comic’s file directly."
        case .fileMissing:
            return "“\(book.displayTitle)” isn’t where it used to be in your comic folder. If the whole folder moved, update its path — that re-links everything at once. If just this file moved or was renamed, choose it directly. Or the server may simply be offline — try again later."
        default:   // .unresolved / .copyFailed
            return "Your comic folder couldn’t be reached — the server may be offline, or the folder may have moved. Update the folder path, choose this file directly, or try again on the right network."
        }
    }

    /// The user re-pointed the whole library folder. Every folder-backed entry now resolves
    /// against the new location by its unchanged relative path, so just retry this open.
    private func handleFolderPicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        do { try LibrarySource.setFolder(url) } catch { return }
        resolveError = nil
        Task { await ensureLocalThenOpen() }
    }

    /// The user picked a replacement file for just this comic. Copy it in now so it opens, and
    /// re-point the entry's source when the pick lives inside the library folder (see
    /// `Importer.relink`). Follows the shipping import path: security scope is taken inside the
    /// detached task, exactly as `LibraryView.runImport` does with a picker URL.
    private func handleReplacementPicked(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let dest = book.archiveURL
        resolveError = nil
        isDownloading = true
        Task {
            do {
                let newRelativePath = try await Task.detached(priority: .userInitiated) {
                    try Importer.relink(from: url, into: dest)
                }.value
                if let newRelativePath { book.sourceRelativePath = newRelativePath }
                book.hasLocalArchive = true
                try? context.save()
                isDownloading = false
                await openStore()
            } catch {
                isDownloading = false
                presentResolve(.copyFailed)
            }
        }
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

    /// Toggle the manual landscape override (session-only): rotate to landscape, or back
    /// to portrait — both work even under the device rotation lock. Reset to portrait when
    /// the reader closes (see the controller's viewWillDisappear).
    private func toggleLandscape() {
        scheduleAutoHide()
        forcedLandscape.toggle()
        OrientationGate.rotate(to: forcedLandscape ? .landscapeRight : .portrait)
    }

    private func reloadPaper() {
        store?.setPaper(enabled: paper.isEnabled, params: paper.params)
        paperVersion += 1
    }

    private func toggleBookmark() {
        scheduleAutoHide()   // keep the chrome up while the user is acting on it
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

/// Shown while a folder-backed comic's archive is being fetched from the library folder. The
/// progress is deliberately indeterminate: a coordinated read over a share doesn't report a
/// reliable byte count, and a spinner that says "working" beats a bar that lies.
private struct ReaderDownloadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.secondary)
            Text("Downloading from your library…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Sits behind the resolve dialog when a folder-backed comic won't fetch, and remains if the
/// user dismisses the dialog without choosing — the reader's Close button is then the way out.
private struct ReaderNotDownloadedView: View {
    var body: some View {
        ContentUnavailableView(
            "Not downloaded",
            systemImage: "icloud.slash",
            description: Text("This comic isn’t on your device yet.")
        )
    }
}

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

/// A request to open a comic, optionally at a specific page (e.g. from a bookmark).
struct ReaderTarget: Identifiable {
    let id = UUID()
    let book: ComicBook
    var page: Int?
}

struct ReaderView: View {
    let book: ComicBook
    /// Page to open on (e.g. a bookmark jump); falls back to the resume page.
    var initialPage: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var paper: PaperSettings
    @EnvironmentObject private var settings: ReaderSettings
    // The reader is a fullScreenCover; `.preferredColorScheme` set on the tab view does
    // not reach it, so it reads the appearance itself to keep the reader background and
    // any presented sheets in the chosen theme.
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
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
    @State private var autoHide: DispatchWorkItem?
    /// Manual landscape override — session-only, not persisted. Toggling it also returns
    /// to portrait, so it's a plain landscape⇄portrait switch for rotation-locked devices.
    @State private var forcedLandscape = false

    private var pageCount: Int { store?.pageCount ?? book.pageCount }
    private var isBookmarked: Bool {
        _ = bookmarkTick
        return book.bookmarks.contains { $0.pageIndex == currentPage }
    }

    var body: some View {
        ZStack {
            readerBackground.ignoresSafeArea()

            if let store {
                ReaderHost(store: store,
                           settings: settings,
                           startIndex: clampedStart(store.pageCount),
                           currentPage: $currentPage,
                           paperVersion: paperVersion,
                           jumpTarget: $jumpTarget,
                           backgroundColor: readerBackgroundUIColor,
                           onToggleChrome: toggleChrome)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
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
        .onAppear(perform: setup)
        .onDisappear {
            autoHide?.cancel()
            // Guaranteed portrait reset on close — a fallback for the controller's
            // viewWillDisappear (which doesn't always fire for a fullScreenCover), so a
            // forced landscape never lingers after leaving the reader.
            OrientationGate.lockPortrait()
        }
        .onChange(of: currentPage) { _, page in
            saveProgress(page)
            if page >= pageCount - 1 { markRead() }
        }
        .onChange(of: paper.isEnabled) { reloadPaper() }
        .onChange(of: paper.params) { reloadPaper() }
        .sheet(isPresented: $showGrid) {
            if let store {
                PageGridView(store: store, pageCount: store.pageCount, current: currentPage) { page in
                    // Persist the selection here (a clean user event) and update the
                    // counter. The scroll itself is driven by jumpTarget inside
                    // updateUIViewController, where a state change wouldn't reliably fire
                    // onChange — so resume-on-reopen would otherwise miss a grid jump.
                    saveProgress(page)
                    currentPage = page
                    jumpTarget = page
                    showGrid = false
                }
            }
        }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        // Standard label colour so the chrome icons are dark on light and white on dark,
        // matching the system reading apps. The buttons sit on `.ultraThinMaterial`.
        .foregroundStyle(.primary)
    }

    private var topBar: some View {
        HStack {
            circleButton("xmark") { saveProgress(currentPage); dismiss() }
            Spacer()
            Text("\(currentPage + 1) / \(pageCount)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
            settingsMenu
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
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 26) {
            barButton(isBookmarked ? "bookmark.fill" : "bookmark", tint: isBookmarked ? .accentColor : .primary) {
                toggleBookmark()
            }
            barButton("square.grid.2x2") { showGrid = true }
            barButton(forcedLandscape ? "rotate.left" : "rotate.right",
                      tint: forcedLandscape ? .accentColor : .primary) {
                toggleLandscape()
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 13)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 10)
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private func barButton(_ icon: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
        }
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

    private func setup() {
        // Orientation is handled in the reader controller's viewWillAppear/viewWillDisappear
        // (standard UIKit lifecycle) so the rotation rides the present/dismiss transition
        // instead of flashing afterwards.
        if store == nil {
            store = PageImageStore(book: book, paperEnabled: paper.isEnabled, paperParams: paper.params)
        }
        currentPage = clampedStart(store?.pageCount ?? 1)
        book.dateOpened = .now
        try? context.save()
        scheduleAutoHide()   // the chrome starts visible, then fades after a moment
    }

    private func clampedStart(_ count: Int) -> Int {
        let base = initialPage ?? book.lastReadPage
        return min(max(base, 0), max(count - 1, 0))
    }

    private func saveProgress(_ page: Int) {
        guard book.lastReadPage != page else { return }
        book.lastReadPage = page
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
            store?.thumbnail(at: page, maxPixel: 420) { image in
                guard let image else { return }
                let name = "\(UUID().uuidString).jpg"
                ImageDownsampler.writeJPEG(image, to: Storage.bookmarkThumbURL(name))
                context.insert(Bookmark(pageIndex: page, thumbName: name, book: book))
                try? context.save()
                bookmarkTick += 1
            }
        }
    }
}

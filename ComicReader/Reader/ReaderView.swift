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

    @State private var store: PageImageStore?
    @State private var currentPage = 0
    @State private var chromeVisible = true
    @State private var paperVersion = 0
    @State private var jumpTarget: Int?
    @State private var showGrid = false
    @State private var bookmarkTick = 0   // nudges the view when bookmarks change
    @State private var autoHide: DispatchWorkItem?

    private var pageCount: Int { store?.pageCount ?? book.pageCount }
    private var isBookmarked: Bool {
        _ = bookmarkTick
        return book.bookmarks.contains { $0.pageIndex == currentPage }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let store {
                ReaderHost(store: store,
                           settings: settings,
                           startIndex: clampedStart(store.pageCount),
                           currentPage: $currentPage,
                           paperVersion: paperVersion,
                           jumpTarget: $jumpTarget,
                           onToggleChrome: toggleChrome,
                           onWillRotate: showChrome)
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
        .onAppear(perform: setup)
        .onDisappear { autoHide?.cancel() }
        .onChange(of: currentPage) { _, page in
            saveProgress(page)
        }
        .onChange(of: paper.isEnabled) { reloadPaper() }
        .onChange(of: paper.params) { reloadPaper() }
        .sheet(isPresented: $showGrid) {
            if let store {
                PageGridView(store: store, pageCount: store.pageCount, current: currentPage) { page in
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
        .foregroundStyle(.white)
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
            barButton(isBookmarked ? "bookmark.fill" : "bookmark", tint: isBookmarked ? .accentColor : .white) {
                toggleBookmark()
            }
            barButton("square.grid.2x2") { showGrid = true }
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

    private func barButton(_ icon: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
        }
    }

    // MARK: Chrome visibility

    /// Reveal the chrome and (re)arm the auto-hide. Also used on rotation so the
    /// status bar is present while the turn animates.
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

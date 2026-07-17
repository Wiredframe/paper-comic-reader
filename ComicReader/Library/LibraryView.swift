//
//  LibraryView.swift
//  Comic Reader
//
//  The "Library" tab: every imported comic in one cover grid (or list), with
//  import, a gallery/list toggle, cover zoom and a random picker. The grid spans
//  the full width — no card wrapper — so the covers get as much room as possible.
//

import SwiftUI
import SwiftData

/// How the library grid is ordered. Persisted as a raw string in @AppStorage.
enum LibrarySort: String, CaseIterable {
    case dateAdded, title
    /// Times opened. One field, both readings: descending = most-opened ("popular"),
    /// ascending = least-opened ("gathering dust") — the existing order toggle covers both.
    case opened
    /// Series, then issue number — "Topolino 2" before "Topolino 10". The order a run of a
    /// series is actually collected in, which no file-name sort can reproduce. Only useful
    /// once comics carry metadata, so the menu hides it until some do.
    case series
}

/// Which layout the Library tab shows. Raw string in @AppStorage, like `LibrarySort`.
enum LibraryViewMode: String, CaseIterable, Identifiable {
    case gallery, list, discover

    var id: String { rawValue }
    static let storageKey = "library.viewMode"
    /// The default for anyone who hasn't chosen: the carousel simply shows the collection off
    /// better than a grid of thumbnails does. Falls back here for an unreadable raw value too.
    static let defaultMode = discover
    static func from(_ raw: String) -> LibraryViewMode { LibraryViewMode(rawValue: raw) ?? defaultMode }

    /// One-shot migration off the old `library.listMode` Bool, so someone sitting in List
    /// mode isn't silently reset to Gallery by the upgrade. Self-deleting; safe to call on
    /// every launch. (Gallery users are unaffected either way — the old key defaulted false.)
    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: storageKey) == nil,
              let wasList = defaults.object(forKey: "library.listMode") as? Bool else { return }
        defaults.set((wasList ? list : gallery).rawValue, forKey: storageKey)
        defaults.removeObject(forKey: "library.listMode")
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var fileOpener: FileOpenCoordinator

    @Query private var books: [ComicBook]

    @AppStorage("library.columns") private var columns = 2
    @AppStorage(LibraryViewMode.storageKey) private var viewModeRaw = LibraryViewMode.defaultMode.rawValue
    @AppStorage("library.sortField") private var sortField = LibrarySort.dateAdded.rawValue
    @AppStorage("library.sortAscending") private var sortAscending = false
    /// "Only Downloaded" — hides folder-backed comics whose bytes aren't local. Off by default.
    @AppStorage("library.onlyDownloaded") private var onlyDownloaded = false

    /// Live search query, bound to the `.searchable` field. Narrows every layout through
    /// `displayedBooks`, matching on title / story title / issue number (see `ComicBook.matches`).
    @State private var searchText = ""

    @State private var showImporter = false
    @State private var importError: String?
    @State private var importProgress: ImportProgress?
    /// A comic opened from outside the app is shown in the carousel, not the reader — this asks
    /// the carousel to centre it. One-shot; the carousel clears it once it's moved.
    @State private var focusBookID: UUID?
    /// Note shown when a comic opened from outside was already in the library (so nothing new
    /// was imported). Nil when there's nothing to say.
    @State private var alreadyImportedNote: String?
    /// The comic being read, and optionally the page to land on — the carousel's bookmark
    /// cards open straight to their page, everything else resumes where it left off.
    @State private var target: ReaderTarget?
    /// The comic whose details are showing, if any. Owned here rather than by the cell, so the
    /// grid presents one sheet instead of one per cover.
    @State private var detailBook: ComicBook?
    /// Set by the detail sheet's "Read" and consumed once the sheet has fully dismissed —
    /// raising the reader before then would collide with the sheet still on screen.
    @State private var pendingReadFromDetail: ComicBook?
    @State private var didAutoOpen = false

    // Multi-select (standard iOS "Select" mode): tap toggles a cover instead of opening it,
    // and a batch of comics can be marked read/unread or deleted at once.
    @State private var selectionMode = false
    @State private var selection = Set<UUID>()
    @State private var confirmingBatchDelete = false
    /// Bumped by the shuffle button in Discover mode — the carousel glides to a random comic
    /// rather than opening one.
    @State private var randomTick = 0
    /// Ties the carousel's cover to the reader it opens, so the cover grows into the reader
    /// instead of the reader sliding up over it — and the reader gets the system's drag-down
    /// dismiss along with it.
    @Namespace private var readerZoom

    /// Live state of a running batch import, driving the progress overlay.
    struct ImportProgress: Equatable { var done: Int; var total: Int }

    private var viewMode: LibraryViewMode { .from(viewModeRaw) }

    private var allSelected: Bool { !books.isEmpty && selection.count == books.count }

    private var navTitle: String {
        guard selectionMode else { return "Library" }
        return selection.isEmpty ? "Select Comics" : "\(selection.count) Selected"
    }

    private var deleteConfirmTitle: String {
        let n = selection.count
        return "Delete \(n) comic\(n == 1 ? "" : "s")?"
    }

    /// Whether any comic carries a series — gates the Series sort, which would otherwise be a
    /// menu entry that does nothing until the library is tagged.
    private var hasSeries: Bool { books.contains { $0.series?.nonEmpty != nil } }

    /// Whether any comic comes from a library folder — gates the "Only Downloaded" filter, which
    /// otherwise would be a control that hides nothing (owned copies are always downloaded).
    private var hasFolderComics: Bool { books.contains { $0.isFolderBacked } }

    /// Books ordered by the current sort choice. Sorted in memory so the field/order can
    /// change live without a new @Query.
    private var sortedBooks: [ComicBook] {
        let ascending: [ComicBook]
        switch LibrarySort(rawValue: sortField) ?? .dateAdded {
        case .dateAdded:
            ascending = books.sorted { $0.dateAdded < $1.dateAdded }
        case .title:
            // By what the cards actually say — "Topolino 1900", not the file name behind it.
            // Tie-break on dateAdded so equal titles keep a stable order across re-queries
            // (sorted(by:) isn't stable), the same way .opened does below.
            ascending = books.sorted {
                let order = $0.displayTitle.localizedStandardCompare($1.displayTitle)
                return order == .orderedSame ? $0.dateAdded < $1.dateAdded
                                             : order == .orderedAscending
            }
        case .opened:
            // Tie-break on dateAdded: a fresh library is all-zero openCount and sorted(by:)
            // isn't guaranteed stable, so ties would otherwise churn between recomputations.
            ascending = books.sorted { ($0.openCount, $0.dateAdded) < ($1.openCount, $1.dateAdded) }
        case .series:
            // Same stability tie-break: sortsBefore is a strict weak ordering, but a tie
            // (same series + issue) would otherwise churn between recomputations.
            ascending = books.sorted {
                if $0.sortsBefore($1) { return true }
                if $1.sortsBefore($0) { return false }
                return $0.dateAdded < $1.dateAdded
            }
        }
        return sortAscending ? ascending : ascending.reversed()
    }

    private var trimmedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `sortedBooks` narrowed by the active filter and the search query — the single list every
    /// layout renders, so both reach the grid, the list and the carousel alike. "Downloaded"
    /// includes owned copies (their archive is always local); only not-yet-fetched folder comics
    /// drop out. Search matches title / story title / issue number (see `ComicBook.matches`).
    private var displayedBooks: [ComicBook] {
        var result = onlyDownloaded ? sortedBooks.filter { $0.hasLocalArchive } : sortedBooks
        if !trimmedQuery.isEmpty { result = result.filter { $0.matches(searchQuery: trimmedQuery) } }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ScrollView { emptyState.padding(.top, 80) }
                } else if displayedBooks.isEmpty {
                    // Nothing to show once narrowed — a blank grid or a zero-item carousel (which
                    // the deck can't render) would be wrong. A search that found nothing says so;
                    // otherwise it's the "Only Downloaded" filter hiding everything.
                    ScrollView {
                        if !trimmedQuery.isEmpty {
                            ContentUnavailableView.search(text: trimmedQuery).padding(.top, 80)
                        } else {
                            filteredEmptyState.padding(.top, 80)
                        }
                    }
                } else if viewMode == .discover {
                    // No ScrollView here: the carousel brings its own, sized to the container,
                    // because it needs the real available height to size its card. It gets
                    // `displayedBooks`, so Discover follows the same sort + filter as the grid.
                    PeekCarouselView(books: displayedBooks, randomTrigger: randomTick,
                                     transitionNamespace: readerZoom, focusID: $focusBookID) { book, page in
                        target = ReaderTarget(book: book, page: page)
                    }
                } else {
                    ScrollView {
                        LibraryGrid(books: displayedBooks, columns: columns, listMode: viewMode == .list,
                                    selectionMode: selectionMode, selectedIDs: selection,
                                    onToggleSelect: toggleSelection,
                                    onShowDetail: { detailBook = $0 }) { target = ReaderTarget(book: $0) }
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Search belongs to the browse layouts, not Discover — the carousel is for
            // serendipity, and a lookup field there reads as the wrong tool. Dropped in that mode
            // (searchText is cleared on the way in, below, so no stale query keeps filtering).
            .comicSearchable(active: viewMode != .discover, text: $searchText)
            .toolbar { toolbar }
            .confirmationDialog(deleteConfirmTitle,
                                isPresented: $confirmingBatchDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteSelected() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the selected comics and their bookmarks from your library.")
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ComicUTType.all,
                      allowsMultipleSelection: true, onCompletion: handleImport)
        .alert("Import failed", isPresented: Binding(get: { importError != nil },
                                                     set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
        .alert("Already imported", isPresented: Binding(get: { alreadyImportedNote != nil },
                                                        set: { if !$0 { alreadyImportedNote = nil } })) {
            Button("OK") { alreadyImportedNote = nil }
        } message: { Text(alreadyImportedNote ?? "") }
        .fullScreenCover(item: $target) { target in
            ReaderView(book: target.book, initialPage: target.page)
                // Resolves against the carousel's cover. In the grid and list there's no source
                // with this id, and the presentation falls back to the standard slide-up.
                .navigationTransition(.zoom(sourceID: target.book.id, in: readerZoom))
        }
        .sheet(item: $detailBook, onDismiss: {
            // Open the reader only now the sheet is gone — presenting a full-screen cover while
            // it was still dismissing raced the two presentations. See `ComicDetailView.onRead`.
            if let book = pendingReadFromDetail {
                pendingReadFromDetail = nil
                target = ReaderTarget(book: book)
            }
        }) { book in
            ComicDetailView(book: book) { pendingReadFromDetail = book }
        }
        .overlay {
            if let progress = importProgress {
                ImportProgressOverlay(done: progress.done, total: progress.total)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: importProgress)
        // Read ComicInfo.xml for comics imported before metadata existed. Here rather than in
        // the app shell because this is the default tab and the one whose cards, sort menu and
        // detail sheet the metadata feeds — a @Query in RootTabView would republish the whole
        // shell on every progress save just to run this once.
        .task { await Importer.backfillMetadata(for: books, into: context) }
        // Present a comic opened from outside the app (Files / "Open With"). onAppear
        // covers arriving here via a tab switch; onChange covers already being here.
        .onAppear(perform: consumePendingOpen)
        .onChange(of: fileOpener.token) { _, _ in consumePendingOpen() }
        // Selecting is meaningless over a carousel — don't strand the user in "3 Selected". And
        // Discover has no search field, so clear the query too, or it would keep narrowing the
        // deck invisibly with no way to see or cancel it.
        .onChange(of: viewModeRaw) { _, raw in
            if LibraryViewMode.from(raw) == .discover { exitSelection(); searchText = "" }
        }
        #if DEBUG
        // Screenshot mode: once the seeded comic lands, present what was asked for. onChange
        // covers the seed arriving after this view; onAppear covers it already being there.
        .onChange(of: books.count) { _, _ in autoPresentIfRequested() }
        .onAppear(perform: autoPresentIfRequested)
        #endif
    }

    #if DEBUG
    /// Opens the first comic in the reader (SCREENSHOT_OPEN_PAGE) or its detail sheet
    /// (SCREENSHOT_DETAIL). One-shot, so a later library change can't reopen it.
    private func autoPresentIfRequested() {
        guard !didAutoOpen else { return }
        // Target a named comic (SCREENSHOT_COMIC) when asked — e.g. the anthology whose detail
        // shows a story index — else fall back to the first comic.
        let chosen = ScreenshotSupport.targetComic
            .flatMap { query in books.first { $0.matches(searchQuery: query) } } ?? books.first
        guard let chosen else { return }
        if ScreenshotSupport.shouldOpenReader {
            didAutoOpen = true
            target = ReaderTarget(book: chosen)
        } else if ScreenshotSupport.shouldOpenDetail {
            didAutoOpen = true
            detailBook = chosen
        }
    }
    #endif

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if selectionMode {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { exitSelection() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected { selection.removeAll() }
                    else { selection = Set(books.map(\.id)) }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { markSelected(read: true) } label: { Label("Mark as Read", systemImage: "checkmark.circle") }
                    Button { markSelected(read: false) } label: { Label("Mark as Unread", systemImage: "circle") }
                    Divider()
                    Button(role: .destructive) { confirmingBatchDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Actions for selected comics")
                .disabled(selection.isEmpty)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // In the carousel, shuffling means "show me something else" — glide the
                    // deck to a random comic instead of yanking the reader open.
                    if viewMode == .discover { randomTick += 1 }
                    else { target = books.randomElement().map { ReaderTarget(book: $0) } }
                } label: {
                    Image(systemName: "shuffle")
                }
                .accessibilityLabel(viewMode == .discover ? "Show a random comic" : "Open a random comic")
                .disabled(books.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    Button { enterSelection() } label: { Label("Select", systemImage: "checkmark.circle") }
                        // A carousel shows one comic at a time — batch selection has nothing to act on.
                        .disabled(books.isEmpty || viewMode == .discover)
                    Divider()
                    Menu {
                        Picker("Sort By", selection: $sortField) {
                            Label("Date Added", systemImage: "calendar").tag(LibrarySort.dateAdded.rawValue)
                            Label("Title", systemImage: "textformat").tag(LibrarySort.title.rawValue)
                            if hasSeries {
                                Label("Series", systemImage: "books.vertical").tag(LibrarySort.series.rawValue)
                            }
                            Label("Times Opened", systemImage: "flame").tag(LibrarySort.opened.rawValue)
                        }
                        Divider()
                        Picker("Order", selection: $sortAscending) {
                            Label("Ascending", systemImage: "arrow.up").tag(true)
                            Label("Descending", systemImage: "arrow.down").tag(false)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    // Only meaningful once some comics live in a library folder; hidden otherwise
                    // so it can't be a toggle that does nothing.
                    if hasFolderComics {
                        Toggle(isOn: $onlyDownloaded) {
                            Label("Only Downloaded", systemImage: "arrow.down.circle")
                        }
                    }
                    Divider()
                    Picker("View", selection: $viewModeRaw) {
                        Label("Gallery", systemImage: "square.grid.2x2").tag(LibraryViewMode.gallery.rawValue)
                        Label("List", systemImage: "list.bullet").tag(LibraryViewMode.list.rawValue)
                        Label("Discover", systemImage: "sparkles").tag(LibraryViewMode.discover.rawValue)
                    }
                    // Column zoom only means something in the gallery grid.
                    if viewMode == .gallery {
                        Divider()
                        Button { columns = max(1, columns - 1) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                        Button { columns = min(4, columns + 1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Import and view options")
            }
        }
    }

    /// Same system empty-state treatment as Recents / Bookmarks. Shown for every view mode.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No comics yet", systemImage: "books.vertical")
        } description: {
            Text("Import a CBZ to get started.")
        } actions: {
            Button { showImporter = true } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Shown when "Only Downloaded" is on but nothing is local — with the one-tap way back out,
    /// so the filter can never strand the user on a blank screen.
    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No downloaded comics", systemImage: "arrow.down.circle")
        } description: {
            Text("Only comics downloaded to this device are shown. Turn the filter off to see everything in your library.")
        } actions: {
            Button { onlyDownloaded = false } label: {
                Label("Show All", systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Selection

    private func enterSelection() {
        selection.removeAll()
        selectionMode = true
    }

    private func exitSelection() {
        selectionMode = false
        selection.removeAll()
    }

    private func toggleSelection(_ book: ComicBook) {
        if selection.contains(book.id) { selection.remove(book.id) }
        else { selection.insert(book.id) }
    }

    private func markSelected(read: Bool) {
        for book in books where selection.contains(book.id) { book.isRead = read }
        try? context.save()
    }

    private func deleteSelected() {
        for book in books where selection.contains(book.id) {
            Importer.delete(book, from: context)
        }
        exitSelection()
    }

    /// Picks up a comic handed over by the app after being opened from outside, and
    /// imports it on the same non-blocking path as the picker — importing it in
    /// `onOpenURL` instead froze the app until the watchdog killed it.
    private func consumePendingOpen() {
        let urls = fileOpener.consumeURLs()
        guard !urls.isEmpty else { return }
        runImport(urls, from: .external)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            runImport(urls, from: .picker)
        }
    }

    /// Where an import came from. The two differ in how they finish: comics opened from
    /// outside are shown in the carousel — the first focused, not opened in the reader — and a
    /// duplicate says so if it was already in the library; the picker just counts failures.
    private enum ImportSource { case picker, external }

    /// Imports `urls` without blocking the UI: the slow half (`Importer.prepare` — copy,
    /// decode, cover) runs off the main thread per file, the insert hops back to the main
    /// context, and a progress overlay tracks "X of N". Comics appear in the grid as each
    /// one lands.
    ///
    /// A comic already in the library isn't imported again: the picker silently skips it
    /// (so re-picking a folder only brings in what's new), and an outside "open" of one that
    /// already exists just opens the copy that's there. Matching is by archive content, so a
    /// renamed duplicate is still caught.
    private func runImport(_ urls: [URL], from source: ImportSource) {
        guard !urls.isEmpty else { return }
        importProgress = ImportProgress(done: 0, total: urls.count)
        Task { @MainActor in
            var failures = 0
            var firstBook: ComicBook?
            var firstWasDuplicate = false
            // What's already imported, by archive content. Snapshotted off the SwiftData
            // models (which can't leave the main actor) and grown as each file lands, so a
            // file that duplicates one earlier in the same batch is skipped too.
            var existing = books.map { Importer.ExistingArchive(id: $0.id, path: $0.archiveURL.path) }
            for url in urls {
                do {
                    let snapshot = existing
                    if let dupID = await Task.detached(priority: .userInitiated, operation: {
                        Importer.duplicate(of: url, among: snapshot)
                    }).value {
                        // Already here — don't add a second copy. An outside open still wants to
                        // show it, so remember which existing book, and that it wasn't new.
                        if firstBook == nil {
                            firstBook = books.first { $0.id == dupID }
                            firstWasDuplicate = true
                        }
                    } else {
                        let prepared = try await Task.detached(priority: .userInitiated) {
                            try Importer.prepare(from: url)
                        }.value
                        let book = Importer.commit(prepared, into: context)
                        existing.append(Importer.ExistingArchive(id: book.id, path: book.archiveURL.path))
                        if firstBook == nil { firstBook = book }
                    }
                } catch {
                    failures += 1
                }
                Importer.discardInboxCopy(at: url)
                importProgress?.done += 1
            }
            importProgress = nil

            switch source {
            case .external:
                if let book = firstBook {
                    // Show it where the library shows comics — centre it in the carousel — rather
                    // than opening the reader. Focus only takes in Discover mode, where the
                    // carousel is on screen; in the grid the comic is simply present.
                    if viewMode == .discover { focusBookID = book.id }
                    if firstWasDuplicate {
                        alreadyImportedNote = "“\(book.displayTitle)” is already in your library."
                    }
                } else {
                    let name = urls[0].deletingPathExtension().lastPathComponent
                    importError = "Couldn't open “\(name)”. It may not be a valid CBZ."
                }
            case .picker:
                if failures > 0 { importError = "Couldn't import \(failures) file(s)." }
            }
        }
    }
}

/// Blocking progress card shown while a batch import runs. The dimmed backdrop makes it
/// clear the app is working (the old synchronous import just froze) while the main thread
/// stays free, so the covers animate in behind it as each import completes.
private struct ImportProgressOverlay: View {
    let done: Int
    let total: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 200)
                    .tint(.accentColor)
                Text("Importing \(min(done + 1, total)) of \(total)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

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

    @State private var showImporter = false
    @State private var importError: String?
    @State private var importProgress: ImportProgress?
    /// The comic being read, and optionally the page to land on — the carousel's bookmark
    /// cards open straight to their page, everything else resumes where it left off.
    @State private var target: ReaderTarget?
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

    /// Books ordered by the current sort choice. Sorted in memory so the field/order can
    /// change live without a new @Query.
    private var sortedBooks: [ComicBook] {
        let ascending: [ComicBook]
        switch LibrarySort(rawValue: sortField) ?? .dateAdded {
        case .dateAdded:
            ascending = books.sorted { $0.dateAdded < $1.dateAdded }
        case .title:
            ascending = books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .opened:
            // Tie-break on dateAdded: a fresh library is all-zero openCount and sorted(by:)
            // isn't guaranteed stable, so ties would otherwise churn between recomputations.
            ascending = books.sorted { ($0.openCount, $0.dateAdded) < ($1.openCount, $1.dateAdded) }
        }
        return sortAscending ? ascending : ascending.reversed()
    }

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ScrollView { emptyState.padding(.top, 80) }
                } else if viewMode == .discover {
                    // No ScrollView here: the carousel brings its own, sized to the container,
                    // because it needs the real available height to size its card. It gets
                    // `sortedBooks`, so Discover follows the same sort menu as the grid — its
                    // segments only filter.
                    PeekCarouselView(books: sortedBooks, randomTrigger: randomTick,
                                     transitionNamespace: readerZoom) { book, page in
                        target = ReaderTarget(book: book, page: page)
                    }
                } else {
                    ScrollView {
                        LibraryGrid(books: sortedBooks, columns: columns, listMode: viewMode == .list,
                                    selectionMode: selectionMode, selectedIDs: selection,
                                    onToggleSelect: toggleSelection) { target = ReaderTarget(book: $0) }
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
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
        .fullScreenCover(item: $target) { target in
            ReaderView(book: target.book, initialPage: target.page)
                // Resolves against the carousel's cover. In the grid and list there's no source
                // with this id, and the presentation falls back to the standard slide-up.
                .navigationTransition(.zoom(sourceID: target.book.id, in: readerZoom))
        }
        .overlay {
            if let progress = importProgress {
                ImportProgressOverlay(done: progress.done, total: progress.total)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: importProgress)
        // Present a comic opened from outside the app (Files / "Open With"). onAppear
        // covers arriving here via a tab switch; onChange covers already being here.
        .onAppear(perform: consumePendingOpen)
        .onChange(of: fileOpener.token) { _, _ in consumePendingOpen() }
        // Selecting is meaningless over a carousel — don't strand the user in "3 Selected".
        .onChange(of: viewModeRaw) { _, raw in
            if LibraryViewMode.from(raw) == .discover { exitSelection() }
        }
        #if DEBUG
        // Screenshot mode: once the seeded comic lands, open it in the reader.
        .onChange(of: books.count) { _, count in
            if ScreenshotSupport.shouldOpenReader, !didAutoOpen, let first = books.first {
                didAutoOpen = true
                target = ReaderTarget(book: first)
            }
        }
        .onAppear {
            if ScreenshotSupport.shouldOpenReader, !didAutoOpen, let first = books.first {
                didAutoOpen = true
                target = ReaderTarget(book: first)
            }
        }
        #endif
    }

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
            Text("Import a CBZ or CBR to get started.")
        } actions: {
            Button { showImporter = true } label: {
                Label("Import", systemImage: "square.and.arrow.down")
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

    /// Picks up a comic (or error) handed over by the app after opening a file from
    /// outside — presents the reader, or shows the import-failure alert.
    private func consumePendingOpen() {
        if let book = fileOpener.consumeBook() { target = ReaderTarget(book: book) }
        if let error = fileOpener.consumeError() { importError = error }
    }

    /// Imports the picked files without blocking the UI: the slow half (`Importer.prepare`
    /// — copy, decode, cover) runs off the main thread per file, the insert hops back to
    /// the main context, and a progress overlay tracks "X of N". Comics appear in the grid
    /// as each one lands.
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            importProgress = ImportProgress(done: 0, total: urls.count)
            Task { @MainActor in
                var failures = 0
                for url in urls {
                    do {
                        let prepared = try await Task.detached(priority: .userInitiated) {
                            try Importer.prepare(from: url)
                        }.value
                        Importer.commit(prepared, into: context)
                    } catch {
                        failures += 1
                    }
                    importProgress?.done += 1
                }
                importProgress = nil
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

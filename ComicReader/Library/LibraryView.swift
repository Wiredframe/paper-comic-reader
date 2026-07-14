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
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context

    @Query private var books: [ComicBook]

    @AppStorage("library.columns") private var columns = 2
    @AppStorage("library.listMode") private var listMode = false
    @AppStorage("library.sortField") private var sortField = LibrarySort.dateAdded.rawValue
    @AppStorage("library.sortAscending") private var sortAscending = false

    @State private var showImporter = false
    @State private var importError: String?
    @State private var openedBook: ComicBook?
    @State private var didAutoOpen = false

    /// Books ordered by the current sort choice. Sorted in memory so the field/order can
    /// change live without a new @Query.
    private var sortedBooks: [ComicBook] {
        let ascending: [ComicBook]
        switch LibrarySort(rawValue: sortField) ?? .dateAdded {
        case .dateAdded:
            ascending = books.sorted { $0.dateAdded < $1.dateAdded }
        case .title:
            ascending = books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        return sortAscending ? ascending : ascending.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    LibraryEmptyState { showImporter = true }
                        .padding(.top, 80)
                } else {
                    LibraryGrid(books: sortedBooks, columns: columns, listMode: listMode) { openedBook = $0 }
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ComicUTType.all,
                      allowsMultipleSelection: true, onCompletion: handleImport)
        .alert("Import failed", isPresented: Binding(get: { importError != nil },
                                                     set: { if !$0 { importError = nil } })) {
            Button("OK") { importError = nil }
        } message: { Text(importError ?? "") }
        .fullScreenCover(item: $openedBook) { book in
            ReaderView(book: book)
        }
        #if DEBUG
        // Screenshot mode: once the seeded comic lands, open it in the reader.
        .onChange(of: books.count) { _, count in
            if ScreenshotSupport.shouldOpenReader, !didAutoOpen, count > 0 {
                didAutoOpen = true
                openedBook = books.first
            }
        }
        .onAppear {
            if ScreenshotSupport.shouldOpenReader, !didAutoOpen, let first = books.first {
                didAutoOpen = true
                openedBook = first
            }
        }
        #endif
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { openedBook = books.randomElement() } label: {
                Image(systemName: "shuffle")
            }
            .disabled(books.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Divider()
                Menu {
                    Picker("Sort By", selection: $sortField) {
                        Label("Date Added", systemImage: "calendar").tag(LibrarySort.dateAdded.rawValue)
                        Label("Title", systemImage: "textformat").tag(LibrarySort.title.rawValue)
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
                Picker("View", selection: $listMode) {
                    Label("Gallery", systemImage: "square.grid.2x2").tag(false)
                    Label("List", systemImage: "list.bullet").tag(true)
                }
                if !listMode {
                    Divider()
                    Button { columns = max(1, columns - 1) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                    Button { columns = min(4, columns + 1) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var failures = 0
            for url in urls where (try? Importer.importComic(from: url, into: context)) == nil {
                failures += 1
            }
            if failures > 0 { importError = "Couldn't import \(failures) file(s)." }
        }
    }
}

private struct LibraryEmptyState: View {
    let onImport: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No comics yet")
                .font(.title3.bold())
            Text("Import a CBZ or CBR to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(action: onImport) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
        }
        .frame(maxWidth: .infinity)
    }
}

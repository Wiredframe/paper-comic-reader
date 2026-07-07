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

struct LibraryView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \ComicBook.dateAdded, order: .reverse) private var books: [ComicBook]

    @AppStorage("library.columns") private var columns = 2
    @AppStorage("library.listMode") private var listMode = false

    @State private var showImporter = false
    @State private var importError: String?
    @State private var openedBook: ComicBook?

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    LibraryEmptyState { showImporter = true }
                        .padding(.top, 80)
                } else {
                    LibraryGrid(books: books, columns: columns, listMode: listMode) { openedBook = $0 }
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

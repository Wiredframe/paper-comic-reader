//
//  CollectionView.swift
//  Comic Reader
//
//  The "Collection" tab: folders + all comics, with import, folder creation,
//  gallery/list toggle and cover zoom (as in the reference app's "…" menu).
//

import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \Folder.name) private var folders: [Folder]
    @Query(filter: #Predicate<ComicBook> { $0.folder == nil },
           sort: \ComicBook.dateAdded, order: .reverse)
    private var books: [ComicBook]
    @Query private var allBooks: [ComicBook]   // for the random picker (incl. folders)

    @AppStorage("library.columns") private var columns = 2
    @AppStorage("library.listMode") private var listMode = false

    @State private var showImporter = false
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var importError: String?
    @State private var openedBook: ComicBook?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !folders.isEmpty {
                        FolderSection(folders: folders)
                    }
                    if !books.isEmpty {
                        Text("Comics")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                        LibraryGrid(books: books, folders: folders,
                                    columns: columns, listMode: listMode) { openedBook = $0 }
                            .libraryCard()
                    } else if folders.isEmpty {
                        LibraryEmptyState { showImporter = true }
                            .padding(.top, 80)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: ComicUTType.all,
                      allowsMultipleSelection: true, onCompletion: handleImport)
        .alert("New Collection", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") { createFolder() }
        }
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
            Button { openedBook = allBooks.randomElement() } label: {
                Image(systemName: "shuffle")
            }
            .disabled(allBooks.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showImporter = true } label: { Label("Import", systemImage: "square.and.arrow.down") }
                Button { showNewFolder = true } label: { Label("New Collection", systemImage: "folder.badge.plus") }
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

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        newFolderName = ""
        guard !name.isEmpty else { return }
        context.insert(Folder(name: name))
        try? context.save()
    }
}

private struct FolderSection: View {
    let folders: [Folder]
    @AppStorage("library.columns") private var columns = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections")
                .font(.title3.bold())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: gridColumns, spacing: LibraryGridMetrics.spacing) {
                ForEach(folders) { folder in
                    NavigationLink {
                        FolderView(folder: folder)
                    } label: {
                        CollectionTile(folder: folder)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LibraryGridMetrics.spacing),
              count: max(1, columns))
    }
}

/// A collection shown as a little stack of cards: the newest cover on top with two
/// blank cards peeking out behind it, plus the name and comic count.
private struct CollectionTile: View {
    let folder: Folder

    private var frontCover: URL? {
        folder.books.sorted { $0.dateAdded > $1.dateAdded }.first?.coverURL
    }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                // Two progressively narrower cards peeking out above the cover.
                shape.fill(Color(.tertiarySystemBackground)).padding(.horizontal, 24).offset(y: -13)
                shape.fill(Color(.secondarySystemBackground)).padding(.horizontal, 12).offset(y: -6)
                front
                    .clipShape(shape)
                    .overlay(shape.stroke(.white.opacity(0.08)))
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.4), radius: 5, y: 3)
            .padding(.top, 13)   // reserve room for the peeking cards

            VStack(spacing: 2) {
                Text(folder.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(folder.books.count) \(folder.books.count == 1 ? "comic" : "comics")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var front: some View {
        if let frontCover {
            DiskImage(url: frontCover, contentMode: .fill)
        } else {
            ZStack {
                shape.fill(Color.accentColor.opacity(0.22))
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.accentColor)
            }
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

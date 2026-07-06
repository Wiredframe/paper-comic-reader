//
//  FolderView.swift
//  Comic Reader
//
//  The comics inside one folder.
//

import SwiftUI
import SwiftData

struct FolderView: View {
    let folder: Folder

    @Environment(\.modelContext) private var context
    @Query(sort: \Folder.name) private var folders: [Folder]
    @AppStorage("library.columns") private var columns = 2
    @AppStorage("library.listMode") private var listMode = false
    @State private var openedBook: ComicBook?

    private var books: [ComicBook] {
        folder.books.sorted { $0.dateAdded > $1.dateAdded }
    }

    var body: some View {
        ScrollView {
            if books.isEmpty {
                ContentUnavailableView("Empty collection",
                                       systemImage: "folder",
                                       description: Text("Move comics here from their menu."))
                    .padding(.top, 80)
            } else {
                LibraryGrid(books: books, folders: folders,
                            columns: columns, listMode: listMode) { openedBook = $0 }
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    context.delete(folder)
                    try? context.save()
                } label: {
                    Label("Delete Collection", systemImage: "trash")
                }
            }
        }
        .fullScreenCover(item: $openedBook) { book in
            ReaderView(book: book)
        }
    }
}

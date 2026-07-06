//
//  ComicReaderApp.swift
//  Comic Reader
//

import SwiftUI
import SwiftData

@main
struct ComicReaderApp: App {

    /// The SwiftData store for the library (books, folders, bookmarks).
    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: ComicBook.self, Folder.self, Bookmark.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// Global settings shared by Settings and the reader.
    @StateObject private var paper = PaperSettings()
    @StateObject private var readerSettings = ReaderSettings()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(paper)
                .environmentObject(readerSettings)
                .onOpenURL { url in
                    // Files opened via the share sheet ("Open in Comic Reader").
                    _ = try? Importer.importComic(from: url, into: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}

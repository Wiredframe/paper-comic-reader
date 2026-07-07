//
//  ComicReaderApp.swift
//  Comic Reader
//

import SwiftUI
import SwiftData
import UIKit

@main
struct ComicReaderApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

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

/// Orientation policy lives here: the app as a whole is portrait-only; the reader
/// opts into landscape while it's on screen (see `OrientationGate`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.mask
    }
}

/// Lets the reader — and only the reader — rotate. The library, bookmarks and
/// settings stay in portrait.
enum OrientationGate {
    /// Allow landscape (called when the reader appears).
    static func unlock() { AppDelegate.mask = .allButUpsideDown }

    /// Back to portrait-only, and rotate the device back if it's currently landscape
    /// (called when the reader closes).
    static func lockPortrait() {
        AppDelegate.mask = .portrait
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

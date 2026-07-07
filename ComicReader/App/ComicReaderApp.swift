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

    /// The SwiftData store for the library (books + bookmarks).
    let modelContainer: ModelContainer = {
        let schema = Schema([ComicBook.self, Bookmark.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // The store predates a schema change (e.g. the Collections/Folders feature
            // was removed) and couldn't migrate automatically. Drop it and start fresh
            // rather than crash on launch — the comic archives on disk are untouched and
            // can be re-imported. Only fires when automatic migration can't reconcile.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: config.url.path + suffix))
            }
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
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
                #if DEBUG
                .task { ScreenshotSupport.seedIfRequested(into: modelContainer.mainContext) }
                #endif
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

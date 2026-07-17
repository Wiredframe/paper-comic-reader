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

    /// Hand-off for comics opened from outside the app (Files, "Open With", share sheet).
    @StateObject private var fileOpener = FileOpenCoordinator()

    init() {
        // Fold the old `library.listMode` Bool into the three-way view mode. Property
        // initializers run before this, but nothing reads @AppStorage until the WindowGroup
        // body below, so it lands in time. Self-deleting — a no-op on every later launch.
        LibraryViewMode.migrateIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(paper)
                .environmentObject(readerSettings)
                .environmentObject(fileOpener)
                .onOpenURL(perform: handleOpenURL)
                .task {
                    // First launch into an empty library gets the bundled demo comics.
                    SampleLibrary.seedIfNeeded(into: modelContainer.mainContext)
                    #if DEBUG
                    // Screenshot scene-setup runs after, so it just steers tab/page on the
                    // already-seeded library (it no-ops on content when the library isn't empty).
                    ScreenshotSupport.seedIfRequested(into: modelContainer.mainContext)
                    #endif
                }
        }
        .modelContainer(modelContainer)
    }

    /// Handles a comic opened from the Files app, another app's "Open With", or the
    /// share sheet.
    ///
    /// Only hands the URL over — the Library imports it. Importing here would run the
    /// copy/decode/cover work on the main actor (`prepare` is nonisolated, but a
    /// synchronous call from here still runs on the caller's thread), which froze the UI
    /// and, since this fires during launch, let the watchdog kill the app before the
    /// comic ever appeared.
    @MainActor
    private func handleOpenURL(_ url: URL) {
        fileOpener.request(url: url)
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
    /// Free rotation while the reader is open — the device orientation decides. The mask
    /// stays permissive so the manual landscape/portrait nudges below work either way.
    static func free() { AppDelegate.mask = .allButUpsideDown }

    /// Nudge the interface to a specific orientation *now* — the reader's manual
    /// landscape/portrait toggle. Works even under the device rotation lock because it's
    /// an explicit request; the mask stays permissive, so turning the device afterwards
    /// still rotates freely.
    static func rotate(to orientation: UIInterfaceOrientationMask) {
        requestOrientation(orientation)
    }

    /// Back to portrait-only (called when the reader closes), rotating the device back if
    /// it's currently landscape.
    static func lockPortrait() {
        AppDelegate.mask = .portrait
        requestOrientation(.portrait)
    }

    /// True while the interface is actually sideways — the reader asks before closing, since
    /// only then does the rotation need to finish first (see `settleDuration`).
    @MainActor static var isLandscape: Bool {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return false }
        return scene.effectiveGeometry.interfaceOrientation.isLandscape
    }

    /// How long to let the rotation settle before revealing what's behind the reader.
    ///
    /// `requestGeometryUpdate`'s trailing closure is an ERROR handler, not a completion — there
    /// is no callback for "the rotation finished", so this is a timed wait rather than a
    /// chained one. It's the system rotation animation's own length; the cost of being wrong is
    /// cosmetic in one direction and a slightly late dismiss in the other.
    static let settleDuration: TimeInterval = 0.35

    private static func requestOrientation(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

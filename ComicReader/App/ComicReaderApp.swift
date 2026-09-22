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
    @State private var paper = PaperSettings()
    @State private var readerSettings = ReaderSettings()

    /// Hand-off for comics opened from outside the app (Files, "Open With", share sheet).
    @State private var fileOpener = FileOpenCoordinator()

    /// The downloads in flight. App-wide because a download outlives the view that started it:
    /// begun in a listing, watched in the reader, still running after either goes away.
    @State private var downloads = DownloadManager()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Fold the old `library.listMode` Bool into the three-way view mode. Property
        // initializers run before this, but nothing reads @AppStorage until the WindowGroup
        // body below, so it lands in time. Self-deleting — a no-op on every later launch.
        LibraryViewMode.migrateIfNeeded()
        // Seed a device-appropriate default column count on first launch (an iPad has room for
        // more than the phone's two). One-shot; leaves a count the user has chosen untouched.
        LibraryGridMetrics.migrateColumnsDefaultIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(paper)
                .environment(readerSettings)
                .environment(fileOpener)
                .environment(downloads)
                .onOpenURL(perform: handleOpenURL)
                .task {
                    // Bin any half-finished download from a run that was killed mid-copy. First
                    // thing, while nothing can be downloading yet (see `clearPartialDownloads`).
                    Storage.clearPartialDownloads()
                    // First launch into an empty library gets the bundled demo comics.
                    SampleLibrary.seedIfNeeded(into: modelContainer.mainContext)
                    #if DEBUG
                    // Screenshot scene-setup runs after, so it just steers tab/page on the
                    // already-seeded library (it no-ops on content when the library isn't empty).
                    ScreenshotSupport.seedIfRequested(into: modelContainer.mainContext)
                    #endif
                    // Caches this device's name for the backup document, which names the library
                    // it came from. UIDevice is main-actor bound and the capture may not be.
                    BackupDevice.refreshName()
                    RecentComicSync.refresh(in: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
        // Leaving the foreground re-checks the widget, which catches what no view reports on its
        // own: a deleted comic, a restored backup. A no-op when nothing it shows has changed.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { RecentComicSync.refresh(in: modelContainer.mainContext) }
        }
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
        if let bookID = RecentComicShared.bookID(from: url) {
            fileOpener.request(comicID: bookID)
            return
        }
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
    ///
    /// Setting the mask is not enough on its own: UIKit resolves the supported orientations
    /// once while it presents, and caches them. Usually that is harmless, because the reader
    /// controller's `viewWillAppear` (which calls this) runs inside the present transition.
    /// A folder-backed comic that still has to download breaks that assumption: the cover is
    /// presented showing `ReaderDownloadingView`, so UIKit caches the app's portrait-only mask,
    /// and the controller only appears once the fetch and the archive open have finished. The
    /// first open after a download then refused to rotate until the reader was closed and
    /// reopened, so tell UIKit to ask again.
    static func free() {
        AppDelegate.mask = .allButUpsideDown
        invalidateSupportedOrientations()
    }

    /// Hold the interface sideways until the reader lets go again, whatever the device is doing.
    /// The reader's own landscape toggle; `free()` above releases it.
    ///
    /// This is a MASK change rather than a one-shot `requestGeometryUpdate`, and that is the
    /// whole point. A nudge is forgotten as soon as the app goes to the background and comes
    /// back, which is exactly how the old forced landscape used to drift out from under the
    /// reader. The mask is what UIKit asks on every resolution, so the hold survives the round
    /// trip without anything having to re-assert it on `scenePhase`.
    ///
    /// Both landscape sides stay in the mask, so with the rotation lock OFF the reader still
    /// flips between them when the device is turned end for end.
    static func holdLandscape() {
        AppDelegate.mask = .landscape
        invalidateSupportedOrientations()
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
        invalidateSupportedOrientations()
    }

    /// Tells UIKit that `AppDelegate.mask` changed, so it re-asks instead of reusing what it
    /// resolved at presentation time.
    ///
    /// Walks the whole presentation chain rather than only the root: the reader is a
    /// fullScreenCover, and it is the topmost presented controller whose orientations actually
    /// decide what the interface does.
    private static func invalidateSupportedOrientations() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              var vc = scene.keyWindow?.rootViewController else { return }
        vc.setNeedsUpdateOfSupportedInterfaceOrientations()
        while let presented = vc.presentedViewController {
            presented.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = presented
        }
    }
}

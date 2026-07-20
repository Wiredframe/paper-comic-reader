//
//  RootTabView.swift
//  Comic Reader
//
//  App shell: Recents / Library / Bookmarks / Settings.
//
//  This used to hand-roll a floating capsule tab bar, because back then the platform had no
//  such thing. iOS 26 renders the native TabView as exactly that — a floating glass capsule —
//  so the copy is gone. Two things fall out with it: the bar is real Liquid Glass instead of a
//  material lookalike, and the tab bar now contributes a genuine safe-area inset, so screens no
//  longer have to reserve bottom space by hand (see `FloatingTabBar.reservedSpace`, deleted).
//

import SwiftUI

struct RootTabView: View {
    /// Not called `Tab`: that would shadow SwiftUI's `Tab` inside the builder below.
    enum Screen: Hashable { case recents, library, bookmarks, settings }

    @State private var screen: Screen = Self.initialScreen
    @Environment(FileOpenCoordinator.self) private var fileOpener
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private static var initialScreen: Screen {
        #if DEBUG
        switch ScreenshotSupport.initialTab {
        case "recents":   return .recents
        case "library":   return .library
        case "bookmarks": return .bookmarks
        case "settings":  return .settings
        default:          break
        }
        #endif
        // Open on Recents — the shelf you actually reach for is "what was I just reading",
        // not the whole collection. A first-run library with nothing opened yet shows Recents'
        // own empty state, which points at the other tabs.
        return .recents
    }

    var body: some View {
        TabView(selection: $screen) {
            Tab("Recents", systemImage: "clock", value: Screen.recents) {
                listingTab(.recents) { RecentsView() }
            }
            Tab("Library", systemImage: "books.vertical", value: Screen.library) {
                listingTab(.library) { LibraryView() }
            }
            Tab("Bookmarks", systemImage: "bookmark", value: Screen.bookmarks) {
                listingTab(.bookmarks) { BookmarksView() }
            }
            Tab("Settings", systemImage: "gearshape", value: Screen.settings) {
                SettingsView()
            }
        }
        .preferredColorScheme(AppAppearance.from(appearanceRaw).colorScheme)
        .tint(.accentColor)
        // A comic opened from outside the app lands in the Library — switch to it so the
        // import progress, the reader it opens, or the failure alert is visible. The token
        // only bumps for those opens, so there's nothing to test: reading `pendingURL` here
        // would race the Library's own onChange, which may already have consumed it.
        .onChange(of: fileOpener.token) { _, _ in screen = .library }
    }

    /// Instantiate a listing view only while its tab is SELECTED. The native TabView otherwise keeps
    /// every visited tab — and its `@Query` — alive at once; holding several large comic queries
    /// resident degraded the whole app (felt even on the unrelated Settings sliders), scaling with
    /// library size. Rendering only the selected listing keeps a single query live at a time. The
    /// cost is that a listing rebuilds (transient state such as scroll position resets) on each
    /// return — cheap next to the persistent lag it removes, and the `@AppStorage` choices (view
    /// mode, sort, columns) survive it.
    @ViewBuilder
    private func listingTab<V: View>(_ tab: Screen, @ViewBuilder _ content: () -> V) -> some View {
        if screen == tab {
            content()
        } else {
            Color.clear
        }
    }
}

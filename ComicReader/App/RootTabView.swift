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
    @EnvironmentObject private var fileOpener: FileOpenCoordinator
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private static var initialScreen: Screen {
        #if DEBUG
        switch ScreenshotSupport.initialTab {
        case "recents":   return .recents
        case "bookmarks": return .bookmarks
        case "settings":  return .settings
        default:          break
        }
        #endif
        return .library
    }

    var body: some View {
        TabView(selection: $screen) {
            Tab("Recents", systemImage: "clock", value: Screen.recents) {
                RecentsView()
            }
            Tab("Library", systemImage: "books.vertical", value: Screen.library) {
                LibraryView()
            }
            Tab("Bookmarks", systemImage: "bookmark", value: Screen.bookmarks) {
                BookmarksView()
            }
            Tab("Settings", systemImage: "gearshape", value: Screen.settings) {
                SettingsView()
            }
        }
        .preferredColorScheme(AppAppearance.from(appearanceRaw).colorScheme)
        .tint(.accentColor)
        // A comic opened from outside the app lands in the Library — switch to it so
        // the newly imported book (and the reader it opens), or the import-failure
        // alert, is visible.
        .onChange(of: fileOpener.token) { _, _ in
            if fileOpener.pendingBook != nil || fileOpener.pendingError != nil { screen = .library }
        }
    }
}

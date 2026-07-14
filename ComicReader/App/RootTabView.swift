//
//  RootTabView.swift
//  Comic Reader
//
//  App shell: Recents / Library / Bookmarks / Settings with a floating capsule
//  tab bar (matching the reference app), forced to the dark look.
//

import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case recents, library, bookmarks, settings }
    @State private var tab: Tab = Self.initialTab
    @EnvironmentObject private var fileOpener: FileOpenCoordinator
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private static var initialTab: Tab {
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
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            content
                .safeAreaInset(edge: .bottom) {
                    FloatingTabBar(selection: $tab).padding(.bottom, 2)
                }
        }
        .preferredColorScheme(AppAppearance.from(appearanceRaw).colorScheme)
        .tint(.accentColor)
        // A comic opened from outside the app lands in the Library — switch to it so
        // the newly imported book (and the reader it opens), or the import-failure
        // alert, is visible.
        .onChange(of: fileOpener.token) { _, _ in
            if fileOpener.pendingBook != nil || fileOpener.pendingError != nil { tab = .library }
        }
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .recents:   RecentsView()
        case .library:   LibraryView()
        case .bookmarks: BookmarksView()
        case .settings:  SettingsView()
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: RootTabView.Tab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            item(.recents, "Recents", "clock")
            item(.library, "Library", "books.vertical")
            item(.bookmarks, "Bookmarks", "bookmark")
            item(.settings, "Settings", "gearshape")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private func item(_ tab: RootTabView.Tab, _ title: String, _ icon: String) -> some View {
        let active = selection == tab
        // Active item is tinted with the accent in both modes (the light-mode accent
        // #FF9500 is legible on white). Inactive items get a higher-contrast label in
        // light mode than the washed-out secondary, closer to the system tab bar.
        let inactiveColor: Color = scheme == .dark ? .secondary : Color.primary.opacity(0.55)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.caption2)
            }
            .foregroundStyle(active ? Color.accentColor : inactiveColor)
            .frame(width: 82, height: 48)
            .background {
                if active { Capsule().fill(Color.accentColor.opacity(scheme == .dark ? 0.16 : 0.18)) }
            }
        }
        .buttonStyle(.plain)
    }
}

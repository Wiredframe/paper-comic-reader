//
//  RootTabView.swift
//  Comic Reader
//
//  App shell: Recents / Collection / Bookmarks / Settings with a floating capsule
//  tab bar (matching the reference app), forced to the dark look.
//

import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable { case recents, collection, bookmarks, settings }
    @State private var tab: Tab = .collection

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            content
                .safeAreaInset(edge: .bottom) {
                    FloatingTabBar(selection: $tab).padding(.bottom, 2)
                }
        }
        .preferredColorScheme(.dark)
        .tint(.accentColor)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .recents:    RecentsView()
        case .collection: CollectionView()
        case .bookmarks:  BookmarksView()
        case .settings:   SettingsView()
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: RootTabView.Tab

    var body: some View {
        HStack(spacing: 2) {
            item(.recents, "Recents", "clock")
            item(.collection, "Collection", "books.vertical")
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
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(title).font(.caption2)
            }
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .frame(width: 82, height: 48)
            .background {
                if active { Capsule().fill(Color.accentColor.opacity(0.16)) }
            }
        }
        .buttonStyle(.plain)
    }
}

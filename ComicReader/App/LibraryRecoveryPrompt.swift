//
//  LibraryRecoveryPrompt.swift
//  Comic Reader
//
//  What the reader is told after the store couldn't be opened (see `LibraryStore`): either that
//  the library is only temporarily unavailable, or, after a reset, the offer to bring it back from
//  the safety snapshot.
//
//  The restore is offered only while the reset is pending, never as a permanent button. A later
//  restore would bring back comics the reader has deleted since, folder comics without their
//  files among them. "Don't Restore" clears the flag, which also lets the snapshot roll again.
//

import SwiftUI
import SwiftData

struct LibraryRecoveryPrompt: ViewModifier {

    let isTemporary: Bool

    @Environment(\.modelContext) private var context
    @State private var alert: Kind?
    // Separate from `alert`, so the title doesn't change under the alert while it animates away.
    @State private var isShowing = false

    private enum Kind: Identifiable {
        case unavailable
        case restore(LibraryBackup)
        case resetWithoutSnapshot

        var id: String {
            switch self {
            case .unavailable:          return "unavailable"
            case .restore:              return "restore"
            case .resetWithoutSnapshot: return "reset"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .task { decide() }
            .alert(title, isPresented: $isShowing, presenting: alert) { kind in
                switch kind {
                case .unavailable, .resetWithoutSnapshot:
                    Button("OK") { finish() }
                case .restore(let snapshot):
                    Button("Restore Library") {
                        LibrarySnapshot.restore(snapshot, into: context)
                        RecentComicSync.refresh(in: context)
                        finish()
                    }
                    Button("Don't Restore", role: .cancel) { finish() }
                }
            } message: { kind in
                switch kind {
                case .unavailable:
                    Text("Your library couldn't be opened right now. Nothing was deleted. Close the app and open it again, and if your device is almost full, free up some space first.")
                case .restore(let snapshot):
                    let date = snapshot.createdAt.formatted(date: .abbreviated, time: .shortened)
                    Text("Your library couldn't be opened, so the app started a new one. A safety copy from \(date) can bring back your comics with their reading progress and bookmarks.")
                case .resetWithoutSnapshot:
                    Text("Your library couldn't be opened, so the app started a new one. The old library was set aside, not deleted. If you have a backup, you can bring it back in Settings with Import Library.")
                }
            }
    }

    private var title: LocalizedStringKey {
        switch alert {
        case .restore:              return "Restore Your Library?"
        case .resetWithoutSnapshot: return "Library Reset"
        default:                    return "Library Unavailable"
        }
    }

    private func decide() {
        if isTemporary {
            alert = .unavailable
        } else if LibraryReset.isPending {
            if let snapshot = LibrarySnapshot.load(), !snapshot.comics.isEmpty {
                alert = .restore(snapshot)
            } else {
                alert = .resetWithoutSnapshot
            }
        }
        isShowing = alert != nil
    }

    private func finish() {
        // A temporary library never set the flag, and must not clear one a previous launch set.
        if !isTemporary { LibraryReset.isPending = false }
        isShowing = false
    }
}

extension View {
    func libraryRecoveryPrompt(isTemporary: Bool) -> some View {
        modifier(LibraryRecoveryPrompt(isTemporary: isTemporary))
    }
}

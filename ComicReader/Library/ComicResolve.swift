//
//  ComicResolve.swift
//  Comic Reader
//
//  "Couldn't load this comic": the one dialog for a folder-backed comic whose bytes
//  wouldn't come. It used to live inside the reader, which was where the only download
//  was; now a download can also be started from a listing and fail there, so the dialog
//  moved out here and both places attach it.
//
//  The three choices cover both real causes without guessing between them: the whole
//  folder moved (update its path, which re-links every entry at once), or just this file
//  did (pick it directly), or the share is simply offline right now (cancel and come back
//  on the right network).
//
//  The failure and the dialog are deliberately two different things. The failure lives with
//  the host and stays until it is really dealt with; the dialog is only a way of asking
//  about it, and it steps aside while a file picker is up. Closing that picker without
//  picking anything therefore lands back on the failure, which is what it used to get wrong,
//  leaving a spinner that ran forever.
//

import SwiftUI
import SwiftData

/// A comic whose source needs sorting out, and why.
struct ComicResolveRequest: Identifiable {
    let book: ComicBook
    let error: LibrarySource.SourceError
    var id: UUID { book.id }
}

extension View {
    /// Ask about `request` whenever one appears. `onResolved` fires once the source is usable
    /// again, with whatever the host wanted to do with the comic in the first place (open it,
    /// download it); `onCancel` fires when the reader decides to give up on it.
    func comicResolve(_ request: Binding<ComicResolveRequest?>,
                      onResolved: @escaping (ComicBook) -> Void,
                      onCancel: @escaping () -> Void = {}) -> some View {
        modifier(ComicResolveModifier(request: request, onResolved: onResolved, onCancel: onCancel))
    }
}

private struct ComicResolveModifier: ViewModifier {
    @Binding var request: ComicResolveRequest?
    let onResolved: (ComicBook) -> Void
    let onCancel: () -> Void

    @Environment(\.modelContext) private var context

    /// Whether the dialog is on screen right now. Separate from `request` on purpose: it goes
    /// down while a picker is up and comes back if that picker returns empty-handed.
    @State private var isAsking = false
    @State private var showFolderPicker = false
    @State private var showFilePicker = false
    @State private var isCopying = false

    func body(content: Content) -> some View {
        content
            .overlay { if isCopying { copyingOverlay } }
            .confirmationDialog("Couldn’t load this comic",
                                isPresented: $isAsking,
                                titleVisibility: .visible) {
                Button("Update Folder Path…") { showFolderPicker = true }
                Button("Choose Another File…") { showFilePicker = true }
                Button("Cancel", role: .cancel) {
                    request = nil
                    onCancel()
                }
            } message: {
                Text(message)
            }
            .fileImporter(isPresented: $showFolderPicker,
                          allowedContentTypes: [.folder], onCompletion: folderPicked)
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: ComicUTType.all, onCompletion: replacementPicked)
            // A new failure raises the dialog. A repeat of one that is still unresolved doesn't
            // need to: it is already being asked about, or was deliberately dismissed.
            .onChange(of: request?.id) { _, id in isAsking = id != nil }
            .onAppear { isAsking = request != nil }
    }

    private var message: String {
        switch request?.error {
        case .notConfigured:
            return String(localized: "This comic comes from a library folder that isn’t set up on this device. Choose the folder, or pick this comic’s file directly.")
        case .fileMissing:
            let title = request?.book.displayTitle ?? String(localized: "This comic")
            return String(localized: "“\(title)” isn’t where it used to be in your comic folder. If the whole folder moved, update its path — that re-links everything at once. If just this file moved or was renamed, choose it directly. Or the server may simply be offline — try again later.")
        default:   // .unresolved / .copyFailed / nothing pending
            return String(localized: "Your comic folder couldn’t be reached — the server may be offline, or the folder may have moved. Update the folder path, choose this file directly, or try again on the right network.")
        }
    }

    /// Shown while a picked replacement file is copied in. Small and centred: in the reader it
    /// sits on the letterbox mat, in a listing over the list, and in both it is the only sign
    /// that the choice is being acted on.
    private var copyingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Copying…").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// The user re-pointed the whole library folder. Every folder-backed entry now resolves
    /// against the new location by its unchanged relative path, so just try this comic again.
    private func folderPicked(_ result: Result<URL, Error>) {
        guard let book = request?.book else { return }
        guard case .success(let url) = result else { return askAgain() }
        do { try LibrarySource.setFolder(url) } catch { return askAgain() }
        request = nil
        onResolved(book)
    }

    /// The user picked a replacement file for just this comic. Copy it in now so it opens, and
    /// re-point the entry's source when the pick lives inside the library folder (see
    /// `Importer.relink`). Follows the shipping import path: security scope is taken inside the
    /// detached task, exactly as `LibraryView.runImport` does with a picker URL.
    private func replacementPicked(_ result: Result<URL, Error>) {
        guard let book = request?.book else { return }
        guard case .success(let url) = result else { return askAgain() }
        let dest = book.archiveURL
        isCopying = true
        Task {
            do {
                let newRelativePath = try await Task.detached(priority: .userInitiated) {
                    try Importer.relink(from: url, into: dest)
                }.value
                if let newRelativePath { book.sourceRelativePath = newRelativePath }
                book.hasLocalArchive = true
                try? context.save()
                isCopying = false
                request = nil
                onResolved(book)
            } catch {
                isCopying = false
                request = ComicResolveRequest(book: book, error: .copyFailed)
                askAgain()
            }
        }
    }

    /// The picker came back without a usable choice, so the failure is still the failure: put the
    /// question back rather than leaving the host waiting on something that will never arrive.
    private func askAgain() {
        guard request != nil else { return }
        isAsking = true
    }
}

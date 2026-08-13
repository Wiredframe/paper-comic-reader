//
//  DownloadManager.swift
//  Comic Reader
//
//  The one place a folder-backed comic's bytes are fetched. Every way of asking for a
//  download goes through here (the listings' menus, the Discover button, the reader
//  opening a comic that isn't local yet), so a comic is only ever fetched once, and the
//  download outlives the view that started it: closing the reader mid-fetch now leaves it
//  running, visible (and cancellable) as a ring in the library.
//
//  The copy layer already did the hard part: `Importer.downloadArchive` reports 0…1 and
//  honours cancellation. What was missing was somewhere to keep the task handle and the
//  progress, which is all this is.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DownloadManager {

    /// One in-flight download's progress, as its own observable object rather than a value in
    /// the dictionary below. That's what keeps a progress tick cheap: a view looks its ticket up
    /// once (tracking `tickets`, which only changes when a download starts or ends) and then
    /// reads `progress` (tracking just this ticket), so a tick re-renders the handful of views
    /// showing THAT comic instead of every cell in the library.
    @Observable
    final class Ticket {
        var progress: Double = 0
    }

    /// A download that failed for a reason the reader has to be told about, and can act on:
    /// the folder moved, the file is gone, the share is offline. Cancellation never lands here.
    /// Held until something answers it (see `ComicResolve`), so switching tabs can't lose it.
    struct Failure: Identifiable {
        let book: ComicBook
        let error: LibrarySource.SourceError
        var id: UUID { book.id }
    }

    /// The downloads in flight, by book id. Changes only when one starts or finishes, so views
    /// that read it aren't on the progress path.
    private(set) var tickets: [UUID: Ticket] = [:]
    /// The failure still waiting to be explained. `ComicResolve` shows and clears it.
    var failure: Failure?

    private var tasks: [UUID: Task<Void, Error>] = [:]

    func ticket(for id: UUID) -> Ticket? { tickets[id] }
    func isDownloading(_ id: UUID) -> Bool { tickets[id] != nil }

    /// Start fetching this comic, or hand back the fetch already running for it. Never a second
    /// copy of the same comic: it would pull the same bytes twice and both would move into the
    /// same archive. A no-op (nil) for an owned copy or one that is already local.
    @discardableResult
    func start(_ book: ComicBook, in context: ModelContext) -> Ticket? {
        if let existing = tickets[book.id] { return existing }
        // A fresh attempt supersedes the last complaint about this comic, and clearing it is also
        // what lets the same failure raise the dialog a second time.
        clearFailure(for: book.id)
        guard let relativePath = book.sourceRelativePath else {
            failure = Failure(book: book, error: .notConfigured)
            return nil
        }
        guard book.isRemote || !Storage.fm.fileExists(atPath: book.archiveURL.path) else { return nil }

        let ticket = Ticket()
        tickets[book.id] = ticket
        let id = book.id
        let dest = book.archiveURL
        tasks[id] = Task { [weak self] in
            do {
                try await Importer.downloadArchive(relativePath: relativePath, into: dest) { value in
                    // Called off-main, roughly once per megabyte.
                    Task { @MainActor in ticket.progress = value }
                }
                self?.finish(id, ticket: ticket, book: book, context: context, error: nil)
            } catch {
                self?.finish(id, ticket: ticket, book: book, context: context, error: error)
                throw error
            }
        }
        return ticket
    }

    /// Stop the download for this comic, if one is running. The slot is freed right here rather
    /// than waiting for the task to notice, so the indicator goes at the tap and a fresh download
    /// can start immediately. The copy itself stops at its next chunk boundary and deletes what it
    /// had written, which is why each run works in a temp file of its own (see `downloadArchive`):
    /// the run winding down must not be able to delete the restart's.
    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        tickets[id] = nil
    }

    /// Hand the pending failure for this comic over to whoever is about to explain it, so the
    /// listing behind doesn't raise a second dialog for the same thing.
    func clearFailure(for id: UUID) {
        if failure?.book.id == id { failure = nil }
    }

    /// Wait for this comic's bytes, starting the fetch if nobody else has. For the reader, which
    /// needs the archive before it can open anything. Throws what the fetch threw, including
    /// `.cancelled` when someone cancelled it from elsewhere.
    func join(_ book: ComicBook, in context: ModelContext) async throws {
        if tickets[book.id] == nil, tasks[book.id] == nil {
            guard start(book, in: context) != nil else {
                // Nothing to fetch (already local), or no source to fetch from, in which case `start` has
                // recorded the failure in that case.
                if let failure, failure.book.id == book.id { throw failure.error }
                return
            }
        }
        guard let task = tasks[book.id] else { return }
        try await task.value
    }

    /// Book-keeping for a finished download, success or not. Flipping `hasLocalArchive` is what
    /// makes the indicator disappear everywhere at once.
    private func finish(_ id: UUID, ticket: Ticket, book: ComicBook,
                        context: ModelContext, error: Error?) {
        // A cancelled download can still finish its last chunk after a replacement has been
        // started, so only the run that still owns the slot may free it.
        if tickets[id] === ticket {
            tickets[id] = nil
            tasks[id] = nil
        }
        switch error {
        case nil:
            // The bytes are there whether or not this run still owns the slot, so the flag is
            // told either way.
            book.hasLocalArchive = true
            try? context.save()
        case let sourceError as LibrarySource.SourceError:
            // A cancellation is a decision, not a fault: nothing to explain.
            if case .cancelled = sourceError { return }
            failure = Failure(book: book, error: sourceError)
        case is CancellationError:
            return
        default:
            failure = Failure(book: book, error: .copyFailed)
        }
    }
}

//
//  FileOpenCoordinator.swift
//  Comic Reader
//
//  Bridges "open a comic from outside the app" (Files "Open", another app's
//  "Open With", the share sheet) to the UI. The app's onOpenURL imports the file
//  and hands the result here; RootTabView switches to the Library and LibraryView
//  presents the reader (or an error).
//

import Foundation

@MainActor
final class FileOpenCoordinator: ObservableObject {

    /// A freshly imported comic waiting to be shown. Consumed by the Library.
    @Published private(set) var pendingBook: ComicBook?

    /// A human-readable import failure to surface, if the opened file couldn't be read.
    @Published private(set) var pendingError: String?

    /// Bumped on every request so views can react via `.onChange` without depending
    /// on the payload types being cleanly Equatable.
    @Published private(set) var token: Int = 0

    func request(book: ComicBook) {
        pendingBook = book
        pendingError = nil
        token &+= 1
    }

    func request(error: String) {
        pendingError = error
        pendingBook = nil
        token &+= 1
    }

    /// Returns the pending book (if any) and clears it, so it's shown only once.
    func consumeBook() -> ComicBook? {
        defer { pendingBook = nil }
        return pendingBook
    }

    /// Returns the pending error (if any) and clears it.
    func consumeError() -> String? {
        defer { pendingError = nil }
        return pendingError
    }
}

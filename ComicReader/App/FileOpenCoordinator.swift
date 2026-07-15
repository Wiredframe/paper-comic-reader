//
//  FileOpenCoordinator.swift
//  Comic Reader
//
//  Bridges "open a comic from outside the app" (Files "Open", another app's
//  "Open With", the share sheet) to the UI. The app's onOpenURL hands the URL here
//  without touching it; RootTabView switches to the Library and LibraryView does the
//  import on its own progress-reporting path, then presents the reader (or an error).
//
//  The URL is passed along rather than imported here on purpose: importing is slow
//  (copy, decode, cover render) and onOpenURL runs on the main actor, so doing the work
//  there froze the app and let the launch watchdog kill it.
//

import Foundation

@MainActor
final class FileOpenCoordinator: ObservableObject {

    /// A comic handed to us from outside, waiting to be imported. Consumed by the Library.
    @Published private(set) var pendingURL: URL?

    /// Bumped on every request so views can react via `.onChange` — a second open of the
    /// same URL is still a new request.
    @Published private(set) var token: Int = 0

    func request(url: URL) {
        pendingURL = url
        token &+= 1
    }

    /// Returns the pending URL (if any) and clears it, so it's imported only once.
    func consumeURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

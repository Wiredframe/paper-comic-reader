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

    /// Comics handed to us from outside, waiting to be imported. Consumed by the Library.
    /// A queue, not a single slot: selecting several files in Files or the share sheet arrives
    /// as separate onOpenURL calls in one runloop turn, so a single slot kept only the last and
    /// silently dropped the rest.
    @Published private(set) var pendingURLs: [URL] = []

    /// Bumped on every request so views can react via `.onChange` — a second open of the
    /// same URL is still a new request.
    @Published private(set) var token: Int = 0

    func request(url: URL) {
        pendingURLs.append(url)
        token &+= 1
    }

    /// Returns the pending URLs (if any) and clears the queue, so each is imported only once.
    func consumeURLs() -> [URL] {
        defer { pendingURLs = [] }
        return pendingURLs
    }
}

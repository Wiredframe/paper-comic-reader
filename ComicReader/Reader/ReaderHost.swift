//
//  ReaderHost.swift
//  Comic Reader
//
//  Bridges the UIKit reader into SwiftUI: reports the current page, forwards taps, applies
//  reading-mode / paper changes, and jumps. The reader is the paging ReaderCollectionController,
//  or the ReaderStripController when the portrait strip is on; both speak `ReaderControlling`.
//

import SwiftUI

/// What the SwiftUI side needs from either reader controller.
@MainActor
protocol ReaderControlling: UIViewController {
    var currentPage: Int { get }
    var onPageChanged: ((Int) -> Void)? { get set }
    var onReachedEnd: (() -> Void)? { get set }
    var onToggleChrome: (() -> Void)? { get set }
    func syncLayoutMode()
    func setBackground(_ color: UIColor)
    func reloadCurrent()
    func jump(to page: Int)
}

extension ReaderCollectionController: ReaderControlling {}

struct ReaderHost: UIViewControllerRepresentable {

    let store: PageImageStore
    let settings: ReaderSettings
    /// The live double-page setting, passed as a plain value rather than read off `settings`.
    /// `ReaderView.body` reads it so that, under `@Observable` fine-grained tracking, a flip of
    /// the reader's own Double-Page toggle re-renders the host and reaches `syncLayoutMode()`
    /// below — `settings` is no longer an `@ObservedObject`, so nothing else would trigger it.
    var doublePage: Bool
    /// Read the whole comic as one continuous strip (see `ReaderStripController`). Decided once,
    /// when the reader is built: the setting lives in Settings, out of reach while reading.
    var portraitStrip: Bool
    let startIndex: Int
    @Binding var currentPage: Int
    var paperVersion: Int
    @Binding var jumpTarget: Int?
    var backgroundColor: UIColor
    var onToggleChrome: () -> Void
    var onReachedEnd: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller: ReaderControlling = portraitStrip
            ? ReaderStripController(store: store, settings: settings, startIndex: startIndex, backgroundColor: backgroundColor)
            : ReaderCollectionController(store: store, settings: settings, startIndex: startIndex, backgroundColor: backgroundColor)
        controller.onPageChanged = { index in
            if currentPage != index { currentPage = index }
        }
        controller.onToggleChrome = onToggleChrome
        controller.onReachedEnd = onReachedEnd
        context.coordinator.controller = controller
        context.coordinator.lastPaperVersion = paperVersion
        return controller
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        guard let controller = context.coordinator.controller else { return }
        // Pick up a live double-page toggle (idempotent — a no-op unless the mode
        // actually changed for the current orientation).
        controller.syncLayoutMode()
        controller.setBackground(backgroundColor)
        if context.coordinator.lastPaperVersion != paperVersion {
            context.coordinator.lastPaperVersion = paperVersion
            controller.reloadCurrent()
        }
        // One-shot jump (page grid / bookmarks), then clear so a later scroll can't
        // re-trigger it.
        if let target = jumpTarget {
            if target != controller.currentPage { controller.jump(to: target) }
            let binding = $jumpTarget
            DispatchQueue.main.async { binding.wrappedValue = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var controller: ReaderControlling?
        var lastPaperVersion = 0
    }
}

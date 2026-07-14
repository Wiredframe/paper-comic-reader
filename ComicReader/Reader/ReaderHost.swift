//
//  ReaderHost.swift
//  Comic Reader
//
//  Bridges the UIKit reader (ReaderCollectionController) into SwiftUI: reports the
//  current page, forwards taps, applies reading-mode / paper changes, and jumps.
//

import SwiftUI

struct ReaderHost: UIViewControllerRepresentable {

    let store: PageImageStore
    @ObservedObject var settings: ReaderSettings
    let startIndex: Int
    @Binding var currentPage: Int
    var paperVersion: Int
    @Binding var jumpTarget: Int?
    var backgroundColor: UIColor
    var onToggleChrome: () -> Void

    func makeUIViewController(context: Context) -> ReaderCollectionController {
        let controller = ReaderCollectionController(store: store, settings: settings, startIndex: startIndex, backgroundColor: backgroundColor)
        controller.onPageChanged = { index in
            if currentPage != index { currentPage = index }
        }
        controller.onToggleChrome = onToggleChrome
        context.coordinator.controller = controller
        context.coordinator.lastPaperVersion = paperVersion
        return controller
    }

    func updateUIViewController(_ controller: ReaderCollectionController, context: Context) {
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
        weak var controller: ReaderCollectionController?
        var lastPaperVersion = 0
    }
}

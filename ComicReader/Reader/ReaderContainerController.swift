//
//  ReaderContainerController.swift
//  Comic Reader
//
//  Holds the reader for the current orientation: the strip (ReaderStripController) in
//  portrait, the paging reader with spreads (ReaderCollectionController) in landscape. A
//  rotation hands the page being read from one to the other. The two stay separate
//  controllers because they share nothing but the page: the strip is one continuous band,
//  the landscape reader pages slot by slot with a fit ladder.
//
//  The hand-over is a cross-fade that rides the system rotation: the outgoing reader is
//  frozen as a snapshot, which turns with the window at its old size and fades out, while
//  the incoming reader is already laid out at the new size underneath and fades in.
//

import UIKit

final class ReaderContainerController: UIViewController, ReaderControlling {

    private let store: PageImageStore
    private let settings: ReaderSettings
    private var backgroundUIColor: UIColor
    private(set) var currentPage: Int

    var onPageChanged: ((Int) -> Void)?
    var onReachedEnd: (() -> Void)?
    var onToggleChrome: (() -> Void)?
    var onDismissRequest: (() -> Void)?

    private var child: ReaderControlling?
    private var childIsLandscape = false
    /// The strip's fit when it was last put away for landscape, so turning back to portrait
    /// finds the band the way it was left. Nil until then: the strip starts from the setting.
    private var stripFitWidth: Bool?
    /// The size a rotation is heading to, from the moment the incoming reader is built at it
    /// until the rotation lands. The container is still at the old size meanwhile.
    private var transitionSize: CGSize?

    init(store: PageImageStore, settings: ReaderSettings, startIndex: Int, backgroundColor: UIColor) {
        self.store = store
        self.settings = settings
        self.currentPage = startIndex
        self.backgroundUIColor = backgroundColor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundUIColor
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Free rotation while reading: the reader follows the device. The rest of the app stays
        // portrait (rolled back in viewWillDisappear below and on close). See OrientationGate.
        OrientationGate.free()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Roll back to portrait as part of the dismiss transition. The page grid is a page
        // sheet, which doesn't fire the presenter's viewWillDisappear, so this only runs when
        // the reader itself is going away.
        OrientationGate.lockPortrait()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // The first reader is built at the first real size, which is what decides its kind.
        if child == nil, view.bounds.width > 0 { install(for: view.bounds.size) }
    }

    /// The reader always fills the container, or during a rotation the size it is heading to.
    /// Set here rather than by autoresizing: a reader installed for a rotation is built at the
    /// NEW size while the container is still at the old one, and must never be laid out at the
    /// old size in between (the landscape reader decides single versus double page from it).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        child?.view.frame = CGRect(origin: .zero, size: transitionSize ?? view.bounds.size)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let landscape = Self.isLandscape(size)
        guard child != nil, landscape != childIsLandscape else {
            // Same kind of reader at the new size (iPad multitasking): it re-fits itself.
            super.viewWillTransition(to: size, with: coordinator)
            return
        }
        // Freeze the outgoing reader, then drop it BEFORE forwarding the transition, so it
        // doesn't start re-fitting itself for a size it won't be around for.
        let snapshot = view.snapshotView(afterScreenUpdates: false)
        removeChild()
        super.viewWillTransition(to: size, with: coordinator)

        transitionSize = size
        install(for: size)
        guard let incoming = child?.view else { transitionSize = nil; return }
        incoming.alpha = 0
        if let snapshot {
            snapshot.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            view.addSubview(snapshot)
        }
        coordinator.animate(alongsideTransition: { _ in
            incoming.alpha = 1
            snapshot?.alpha = 0
            // Keep the old picture centred as the window turns; its size stays, so it turns
            // as one rigid page rather than stretching.
            snapshot?.center = CGPoint(x: size.width / 2, y: size.height / 2)
        }, completion: { [weak self] _ in
            snapshot?.removeFromSuperview()
            incoming.alpha = 1
            self?.transitionSize = nil
            self?.view.setNeedsLayout()
        })
    }

    // MARK: ReaderControlling

    func syncLayoutMode() { child?.syncLayoutMode() }

    func setBackground(_ color: UIColor) {
        backgroundUIColor = color
        viewIfLoaded?.backgroundColor = color
        child?.setBackground(color)
    }

    func reloadCurrent() { child?.reloadCurrent() }

    func jump(to page: Int) { child?.jump(to: page) }

    // MARK: Children

    private static func isLandscape(_ size: CGSize) -> Bool { size.width > size.height }

    private func install(for size: CGSize) {
        let landscape = Self.isLandscape(size)
        let reader: ReaderControlling = landscape
            ? ReaderCollectionController(store: store, settings: settings, startIndex: currentPage,
                                         backgroundColor: backgroundUIColor)
            : ReaderStripController(store: store, settings: settings, startIndex: currentPage,
                                    backgroundColor: backgroundUIColor, fitWidth: stripFitWidth)
        reader.onPageChanged = { [weak self] page in
            guard let self else { return }
            self.currentPage = page
            self.onPageChanged?(page)
        }
        reader.onReachedEnd = { [weak self] in self?.onReachedEnd?() }
        reader.onToggleChrome = { [weak self] in self?.onToggleChrome?() }
        reader.onDismissRequest = { [weak self] in self?.onDismissRequest?() }

        addChild(reader)
        reader.view.frame = CGRect(origin: .zero, size: size)
        view.addSubview(reader.view)
        reader.didMove(toParent: self)
        child = reader
        childIsLandscape = landscape
    }

    private func removeChild() {
        guard let child else { return }
        if let strip = child as? ReaderStripController { stripFitWidth = strip.fitWidth }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        self.child = nil
    }
}

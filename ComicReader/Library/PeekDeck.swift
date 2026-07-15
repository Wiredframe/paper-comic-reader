//
//  PeekDeck.swift
//  Comic Reader
//
//  The peek carousel itself: fixed-width slots holding one large, uncropped image centred with
//  its neighbours peeking in either side, snapped with viewAligned. It knows nothing about what
//  it's showing — the Library deals it comic covers, the Bookmarks tab bookmarked pages.
//
//  This is feel-critical and the centring and shadow room below each took a couple of passes to
//  get right. It lives here so there is exactly one copy to get right.
//

import SwiftUI

/// Everything the deck needs to draw one slot. The image file is expected to be stored at
/// `ImageDownsampler.libraryCardPixel` already (covers and bookmark shots both are).
struct PeekArt {
    var url: URL?
    /// width / height of the artwork. Drives the uncropped sizing — `DiskImage` fills whatever
    /// frame it's handed and can't report the shape itself, so it has to be known up front.
    var aspect: Double
    var label: String
}

/// The item the deck centres on. The deck and whatever draws a panel beside it must not
/// disagree about the answer, and before the first scroll reports an id there isn't one yet —
/// so both resolve it through here, falling back to the first item.
func peekCentered<Item: Identifiable>(in items: [Item], id: Item.ID?) -> Item? {
    if let id, let match = items.first(where: { $0.id == id }) { return match }
    return items.first
}

struct PeekDeck<Item: Identifiable>: View where Item.ID == UUID {
    /// Already in the order they should appear — ordering is the caller's business.
    let items: [Item]
    @Binding var centeredID: UUID?
    let art: (Item) -> PeekArt
    /// Called when the centred slot is tapped. Tapping a neighbour centres it instead.
    let onOpen: (Item) -> Void
    /// Supply this, and pair it with `.navigationTransition(.zoom(sourceID:in:))` on whatever
    /// the tap presents, to have the art itself grow into the presented view rather than a
    /// sheet sliding up over it. It also buys the presentation a native interactive dismiss —
    /// the same drag-it-back-down the system uses everywhere else.
    var transitionNamespace: Namespace.ID? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of each neighbour stays visible either side — this is what makes it a peek
    /// carousel, and it (not a height percentage) is what bounds the image's size.
    private let peekInset: CGFloat = 52
    private let slotSpacing: CGFloat = 14
    // Room for the shadow, which the ScrollView would otherwise clip. A Gaussian blur spreads
    // roughly 1.5x its radius, so `.shadow(radius: 18, y: 8)` actually reaches about
    // 27 + 8 = 35pt below the art and 27 - 8 = 19pt above — not the 26/10 the radius alone
    // suggests. Asymmetric on purpose: reserving the same both sides wasted room up top and
    // still clipped the tail against whatever sits underneath.
    private let shadowTop: CGFloat = 20
    private let shadowBottom: CGFloat = 40

    private var centered: Item? { peekCentered(in: items, id: centeredID) }

    var body: some View {
        GeometryReader { geo in carousel(in: geo.size) }
    }

    private func carousel(in size: CGSize) -> some View {
        // The slot is what the peek leaves over; the art then fills it (unless it's so tall
        // that the height caps it first — see `card`).
        let slotW = max(120, size.width - 2 * peekInset)
        // Read once here: `.scrollTransition`'s closure is @Sendable and can't touch
        // main-actor state like the environment.
        let animate = !reduceMotion

        return ScrollView(.horizontal) {
            LazyHStack(spacing: slotSpacing) {
                ForEach(items) { item in
                    card(item, slotW: slotW, boxH: size.height)
                        .frame(width: slotW)
                        // Visual only — the layout keeps a clean, even stride, so viewAligned
                        // still snaps each card dead centre while they visually overlap.
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(animate ? 1 - 0.14 * abs(phase.value) : 1)
                                .offset(x: animate ? -phase.value * 26 : 0)   // pull neighbours inward
                                .opacity(animate ? 1 - 0.3 * abs(phase.value) : 1)
                        }
                        .zIndex(centered?.id == item.id ? 1 : 0)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        // These margins are what let the first and last card reach the middle — and together
        // with viewAligned they ARE the centring. Note there is deliberately no
        // `anchor: .center` on scrollPosition below: that would centre a second time, pushing
        // every card one full inset to the right.
        .contentMargins(.horizontal, max(0, (size.width - slotW) / 2), for: .scrollContent)
        .scrollPosition(id: $centeredID)
        .sensoryFeedback(.selection, trigger: centeredID)
    }

    private func card(_ item: Item, slotW: CGFloat, boxH: CGFloat) -> some View {
        let art = art(item)
        // Width-driven: the art fills its slot, and only a very tall image gets capped by the
        // height left once the shadow has room. Either way it is never cropped.
        let artH = min(max(80, boxH - shadowTop - shadowBottom), slotW / art.aspect)
        let artW = artH * art.aspect
        // Resolved through `centered` so the first card counts as centred before any scroll has
        // reported an id — otherwise its first tap would try to centre it instead of opening it.
        let isCentered = centered?.id == item.id

        // Spacers with different minimums: the art still sits about centred when there's room
        // to spare, but can never come closer to either edge than its shadow needs.
        return VStack(spacing: 0) {
            Spacer(minLength: shadowTop)
            transitionSource(image(art, width: artW, height: artH), id: item.id)
            Spacer(minLength: shadowBottom)
        }
            .frame(width: slotW, height: boxH)
            .contentShape(Rectangle())
            .onTapGesture {
                if isCentered {
                    onOpen(item)      // its details are already on screen — a tap just opens it
                } else {
                    withAnimation(.snappy(duration: 0.28)) { centeredID = item.id }
                }
            }
    }

    /// Anchors the zoom transition on the art itself — not the slot, which is the full peek
    /// width and mostly empty, so anchoring there would grow the reader out of a transparent
    /// box around the cover rather than out of the cover. No-op for callers that don't want a
    /// zoom (`.matchedTransitionSource` takes no optional namespace, hence the branch).
    @ViewBuilder
    private func transitionSource(_ view: some View, id: UUID) -> some View {
        if let transitionNamespace {
            view.matchedTransitionSource(id: id, in: transitionNamespace)
        } else {
            view
        }
    }

    private func image(_ art: PeekArt, width: CGFloat, height: CGFloat) -> some View {
        DiskImage(url: art.url, contentMode: .fit,
                  maxPixel: ImageDownsampler.libraryCardPixel)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
            .accessibilityLabel(art.label)
    }
}

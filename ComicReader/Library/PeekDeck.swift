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

/// The art's own look. Its own type because `PeekDeck` is generic and generic types can't hold
/// static stored properties — but it needs to be shared, because the zoom transition's source
/// configuration has to draw the same rounding and the same shadow as the card. Let those drift
/// and the transition renders a bare rectangle with the shadow snapping in at the end.
private enum ArtStyle {
    static let corner: CGFloat = 14
    static let shadowColor = Color.black.opacity(0.4)
    static let shadowRadius: CGFloat = 18
    static let shadowOffsetY: CGFloat = 8
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
    /// Points → pixels, so a slot decodes its art at exactly its on-screen size (see `image`).
    @Environment(\.displayScale) private var displayScale

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

    /// How wide one slot is. On a phone in any orientation, and on an iPad held upright, it's the
    /// full width less the two peeks — the single centred hero the deck is designed around. But an
    /// iPad in landscape is wide and short: a lone cover there is capped small by the height and
    /// left stranded in empty margin. On that one shape, size the slot to about a single cover's
    /// natural width so as many as fit sit side by side — still snapped one at a time, still with
    /// the outermost cut off at the edges to invite a swipe.
    private func slotWidth(in size: CGSize) -> CGFloat {
        let singleHero = max(120, size.width - 2 * peekInset)
        // Wide AND short — i.e. iPad landscape only. 1000pt clears every iPad's landscape width
        // while staying comfortably above the largest iPhone's, so no iPhone and no upright iPad
        // is touched: they all keep the untouched single-hero deck.
        guard size.width > size.height, size.width >= 1000 else { return singleHero }
        let coverHeight = max(80, size.height - shadowTop - shadowBottom)
        let heroWidth = coverHeight * (2.0 / 3.0)   // a typical comic cover at this height
        // Floored so covers never shrink to thumbnails, and capped at the single-hero width so
        // this can only ever add covers beside the centre, never blow one up past the phone size.
        return min(singleHero, max(320, heroWidth + 56))
    }

    private func carousel(in size: CGSize) -> some View {
        // The slot is what the peek leaves over; the art then fills it (unless it's so tall
        // that the height caps it first — see `card`).
        let slotW = slotWidth(in: size)
        // Read once here: `.scrollTransition`'s closure is @Sendable and can't touch
        // main-actor state like the environment.
        let animate = !reduceMotion

        return ScrollView(.horizontal) {
            LazyHStack(spacing: slotSpacing) {
                ForEach(items) { item in
                    card(item, slotW: slotW, boxH: size.height)
                        .frame(width: slotW)
                        // Visual only: the centred card sits full-size, its neighbours a touch
                        // smaller and dimmer. Deliberately NO horizontal offset. Pulling the cards
                        // inward looked nice at rest, but the offset released to zero right as a
                        // card reached the centre — an extra sideways nudge layered on the scroll,
                        // peaking exactly at the snap, which read as a jerk at the end of a slow
                        // swipe. Scale and opacity only change size and alpha, never position, so
                        // they stay smooth through the snap. With no inward pull the cards no longer
                        // overlap, so the centred-card zIndex it needed is gone too.
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(animate ? 1 - 0.14 * abs(phase.value) : 1)
                                .opacity(animate ? 1 - 0.3 * abs(phase.value) : 1)
                        }
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
    ///
    /// The configuration is what keeps the shadow alive through the transition. Left to
    /// itself the zoom draws the source as a plain rectangle: the shadow is clipped away for
    /// the whole animation and then reappears the instant the real card is back, with nothing
    /// tweening it. Handing the same rounding and shadow to the source makes the transition
    /// draw them, so there's nothing to snap back to.
    @ViewBuilder
    private func transitionSource(_ view: some View, id: UUID) -> some View {
        if let transitionNamespace {
            view.matchedTransitionSource(id: id, in: transitionNamespace) { config in
                config
                    .clipShape(.rect(cornerRadius: ArtStyle.corner, style: .continuous))
                    .shadow(color: ArtStyle.shadowColor,
                            radius: ArtStyle.shadowRadius,
                            y: ArtStyle.shadowOffsetY)
            }
        } else {
            view
        }
    }

    private func image(_ art: PeekArt, width: CGFloat, height: CGFloat) -> some View {
        // Decode to the art's ACTUAL on-screen size (points × scale), capped at the stored ceiling —
        // not a flat libraryCardPixel. A peek neighbour, and every slot on an iPad in landscape's
        // multi-cover mode, is far smaller than one hero, so decoding them all at the ceiling pinned
        // memory for pixels never shown. Sizing to the frame shrinks the decoded bitmap on every
        // device while the centred hero (which fills the deck) still decodes at full resolution.
        DiskImage(url: art.url, contentMode: .fit,
                  maxPixel: min(ImageDownsampler.libraryCardPixel, max(width, height) * displayScale))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: ArtStyle.corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ArtStyle.corner, style: .continuous)
                .stroke(Color.primary.opacity(0.1)))
            .shadow(color: ArtStyle.shadowColor, radius: ArtStyle.shadowRadius, y: ArtStyle.shadowOffsetY)
            .accessibilityLabel(art.label)
    }
}

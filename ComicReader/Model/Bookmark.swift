//
//  Bookmark.swift
//  Comic Reader
//
//  SwiftData model for a bookmarked page. The thumbnail (a screenshot of that
//  exact page) is a file on disk in Storage.bookmarkThumbs.
//

import Foundation
import SwiftData

@Model
final class Bookmark {

    @Attribute(.unique) var id: UUID
    var pageIndex: Int          // 0-based
    var thumbName: String       // thumbnail file in Storage.bookmarkThumbs
    var dateAdded: Date
    var book: ComicBook?
    var pageAspect: Double?     // page width / height, captured when the bookmark is made.
                                // Stored for the same reason as ComicBook.coverAspect: the
                                // carousel has to size an uncropped card up front, and
                                // DiskImage fills whatever frame it's given rather than
                                // reporting the shape. Comic pages vary far more than covers
                                // do — a double-page spread is wider than it is tall.
                                // Optional, so migration stays additive.

    // MARK: Story
    //
    // Which story in the comic's index this page belongs to. ComicInfo puts NO page number and no
    // page range on a story (see ComicStory: number, kind, title, code, credits, and nothing
    // positional), so this can never be worked out — the reader says so by hand, from the
    // bookmark's own menu.
    //
    // Three fields rather than one reference, because `ComicBook.stories` is a plain Codable
    // attribute that `ComicBook.apply(_:)` REPLACES wholesale on every metadata read: import,
    // `Importer.backfillMetadata`, and the user-facing "Re-read Metadata" in Settings. A stored
    // offset alone would silently come to point at a different story after a re-read, and a stored
    // `ComicStory.number` isn't identity at all (ComicMetadataSection says why: it's parsed free
    // text and a tagger can repeat it). So the DISPLAY value is denormalised and the other two are
    // only hints for finding the row again — see `resolvedStoryIndex()`. All three are Optional
    // with no initializer, so migration stays additive, and none is an `init` parameter, so
    // creating a bookmark is unchanged.

    /// The story's title as it read when the user picked it. The single source of truth for every
    /// caption: it stays right even if the index is later re-parsed differently, reordered, or
    /// disappears. Never cleared automatically — a reworded summary must not drop an assignment
    /// somebody made by hand.
    var storyTitle: String?

    /// The offset the story sat at in `book.stories` when it was picked. A position, not
    /// `ComicStory.number`, for the reason above. A hint only: re-checked before it's trusted.
    var storyIndex: Int?

    /// The INDUCKS-style story code ("I TL 1900-A"), when the tagger wrote one. The most stable
    /// identity a story has, so it's tried first when re-finding the row.
    var storyCode: String?

    init(id: UUID = UUID(), pageIndex: Int, thumbName: String,
         pageAspect: Double? = nil, book: ComicBook? = nil) {
        self.id = id
        self.pageIndex = pageIndex
        self.thumbName = thumbName
        self.dateAdded = .now
        self.pageAspect = pageAspect
        self.book = book
    }

    var thumbURL: URL { Storage.bookmarkThumbURL(thumbName) }

    /// "Page 12" — the caption on every bookmark card, row and panel.
    var pageLabel: String { "Page \(pageIndex + 1)" }

    /// Whether a story has been assigned at all.
    var hasStory: Bool { storyTitle?.nonEmpty != nil }

    /// The assigned story's title, or nil. Read straight from the stored value rather than looked
    /// up in `book.stories`: the lookup can fail (the index was re-parsed) while the title the
    /// reader chose is still true of the page, and every caption wants the title either way.
    var storyLabel: String? { storyTitle?.nonEmpty }

    /// Where the assigned story sits in `book.stories` RIGHT NOW, or nil when the link no longer
    /// resolves to a row. Only the picker needs this, to tick the current row — anything that
    /// merely displays a bookmark reads `storyLabel`, which already holds the display value.
    ///
    /// Deliberately PURE: it never writes the healed offset back. A getter that repaired the model
    /// would dirty the context on every render; the picker rewrites all three fields when it
    /// commits, which is when drift actually gets repaired.
    ///
    /// Tried in order of how much each identity is worth trusting:
    ///  1. the code, when the tagger wrote one and exactly one story carries it;
    ///  2. the remembered offset, but only if the title there still matches — so a re-read that
    ///     left the index alone costs one string compare;
    ///  3. the title, when exactly one story has it (the row moved);
    ///  4. otherwise nil. The assignment still stands; it just has no row to point at any more.
    func resolvedStoryIndex() -> Int? {
        guard let title = storyTitle?.nonEmpty,
              let stories = book?.stories, !stories.isEmpty else { return nil }
        if let code = storyCode?.nonEmpty {
            let byCode = stories.indices.filter { stories[$0].code?.nonEmpty == code }
            if byCode.count == 1 { return byCode[0] }
        }
        if let index = storyIndex, stories.indices.contains(index), stories[index].title == title {
            return index
        }
        let byTitle = stories.indices.filter { stories[$0].title == title }
        return byTitle.count == 1 ? byTitle[0] : nil
    }

    /// Links this page to the story at `index` in its comic's index, capturing the title and the
    /// code alongside the position. An out-of-range index (a picker left open across a metadata
    /// re-read) clears instead, which is the honest outcome: the row it pointed at is gone.
    func assignStory(at index: Int) {
        guard let stories = book?.stories, stories.indices.contains(index),
              let title = stories[index].title.nonEmpty else {
            clearStory()
            return
        }
        storyIndex = index
        storyTitle = title
        storyCode = stories[index].code?.nonEmpty
    }

    func clearStory() {
        storyIndex = nil
        storyTitle = nil
        storyCode = nil
    }
}

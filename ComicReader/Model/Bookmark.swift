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
    // bookmark's own menu or the reader's bookmark button. A comic without an index can still get
    // a story: a name typed in the picker (`assignCustomStory`), held in `storyTitle` alone.
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
    var pageLabel: String { String(localized: "Page \(pageIndex + 1)") }

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

    /// Names this page's story by hand, for a comic whose index doesn't list it (or that has no
    /// index at all, like most collected editions). Only the display value is set: there is no row
    /// to point at, and `resolvedStoryIndex()` already treats a title it can't find as an
    /// assignment that simply has no row. A blank name clears instead.
    func assignCustomStory(_ title: String) {
        guard let title = title.nonEmpty else {
            clearStory()
            return
        }
        storyIndex = nil
        storyTitle = title
        storyCode = nil
    }

    /// Takes over a suggestion: the index row when it still resolves to one, the bare name otherwise.
    func assign(_ suggestion: StorySuggestion) {
        if let index = suggestion.storyIndex {
            assignStory(at: index)
        } else {
            assignCustomStory(suggestion.title)
        }
    }

    func clearStory() {
        storyIndex = nil
        storyTitle = nil
        storyCode = nil
    }

    // MARK: Search

    /// Whether this bookmark matches a Bookmarks search `query`. Its own story first, then its
    /// comic's names, but NOT the comic's story index: a story title found there would match every
    /// bookmark of the issue, when the reader looking for a story wants the pages that belong to
    /// it. Same case- and diacritic-insensitive compare as `ComicBook.matches`.
    func matches(searchQuery query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if let story = storyLabel,
           story.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }
        return book?.matches(searchQuery: trimmed, includingStories: false) ?? false
    }

    // MARK: Story runs

    /// Consecutive bookmarks that share a story (or share having none), for a per-comic list that
    /// puts a header over each story.
    struct StoryRun: Identifiable {
        let title: String?
        let marks: [Bookmark]
        /// The first mark's id: stable while the run keeps its first page.
        var id: UUID { marks[0].id }
    }

    /// Splits `marks`, already in page order, into runs of the same story label. A story that
    /// comes back after another one starts a new run, so the runs follow the pages.
    static func storyRuns(_ marks: [Bookmark]) -> [StoryRun] {
        var runs: [StoryRun] = []
        var current: [Bookmark] = []
        for mark in marks {
            if let first = current.first, first.storyLabel != mark.storyLabel {
                runs.append(StoryRun(title: first.storyLabel, marks: current))
                current = []
            }
            current.append(mark)
        }
        if let first = current.first { runs.append(StoryRun(title: first.storyLabel, marks: current)) }
        return runs
    }

    // MARK: Suggestion

    /// A story guessed from the neighbouring bookmarks. Stories run over consecutive pages, so a
    /// page that sits between two marks of the same story almost certainly belongs to it, and one
    /// after a mark most likely continues that mark's story.
    struct StorySuggestion: Equatable {
        let title: String
        /// The row in the comic's index, when the neighbour's assignment resolves to one. Nil for a
        /// name given by hand.
        let storyIndex: Int?
        /// The 0-based page of the mark the suggestion was taken from.
        let page: Int
        /// The 0-based page of the mark on the far side, when both neighbours agree.
        let otherPage: Int?

        /// Whether the marks on both sides of the page name this story.
        var isStrong: Bool { otherPage != nil }
    }

    /// The story this page most likely belongs to, judged by the other bookmarks of its comic. Nil
    /// when none of them has a story, or when the guess is already this page's story.
    func suggestedStory() -> StorySuggestion? {
        guard let book else { return nil }
        let others = book.bookmarks.filter { $0.id != id }
        guard let suggestion = Self.suggestedStory(forPage: pageIndex, among: others),
              suggestion.title != storyLabel else { return nil }
        return suggestion
    }

    /// The suggestion rule on its own, so it can be tested without a picker:
    ///  1. the nearest marks below and above that carry a story both name the same one: that one,
    ///     as a strong suggestion;
    ///  2. otherwise the nearest one below (the story that was running when this page came up);
    ///  3. otherwise the nearest one above, for a page before the first assigned mark.
    /// Two marks name the same story when both resolve to the same index row, or, when either has
    /// no row (a name given by hand), when their titles match.
    static func suggestedStory(forPage page: Int, among marks: [Bookmark]) -> StorySuggestion? {
        let assigned: [(page: Int, title: String, index: Int?)] = marks.compactMap { mark in
            guard mark.pageIndex != page, let title = mark.storyLabel else { return nil }
            return (mark.pageIndex, title, mark.resolvedStoryIndex())
        }
        let lower = assigned.filter { $0.page < page }.max { $0.page < $1.page }
        let higher = assigned.filter { $0.page > page }.min { $0.page < $1.page }
        if let lower, let higher {
            let same: Bool
            if let a = lower.index, let b = higher.index { same = a == b } else { same = lower.title == higher.title }
            if same {
                return StorySuggestion(title: lower.title, storyIndex: lower.index,
                                       page: lower.page, otherPage: higher.page)
            }
        }
        guard let nearest = lower ?? higher else { return nil }
        return StorySuggestion(title: nearest.title, storyIndex: nearest.index,
                               page: nearest.page, otherPage: nil)
    }
}

//
//  StoryPickerView.swift
//  Comic Reader
//
//  Assigning a bookmark to one of the stories in its comic's ComicInfo index. ComicInfo puts no
//  page numbers on a story, so nothing can derive this — here is where the reader says which story
//  a bookmarked page belongs to.
//
//  The list is deliberately the SAME `StoryRow` the detail view draws, in the same rounded block:
//  this is the index you already know from "Details", with a tick added. Rows are identified by
//  ARRAY OFFSET, never `ComicStory.number` — see ComicMetadataSection for why.
//
//  Above the index sits a suggestion taken from the neighbouring bookmarks (stories run over
//  consecutive pages), and below it the names typed by hand for this comic plus "New Story…", so
//  a comic with no index, like most collected editions, can still group its pages into stories.
//
//  Presented by the SCREEN, not by a card: one sheet per screen (BookmarksView owns one for all
//  three of its layouts, PeekCarouselView one for the Discover detail page), the same way
//  LibraryView owns `detailBook` while CoverCell only hands a comic up.
//

import SwiftUI
import SwiftData

struct StoryPickerView: View {
    let bookmark: Bookmark

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// The "New Story…" row turns into a text field in place, rather than pushing another screen
    /// for one line of text.
    @State private var isNaming = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    private var stories: [ComicStory] { bookmark.book?.stories ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    list
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Assign to Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
    }

    /// Which page this is about. The sheet is opened from several places and not all of them stay
    /// on screen behind it, so it names the page itself, with the page shot to recognise it by.
    private var header: some View {
        HStack(spacing: 12) {
            DiskImage(url: bookmark.thumbURL, contentMode: .fill, maxPixel: 260)
                .frame(width: 44, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.book?.displayTitle ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(bookmark.pageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var list: some View {
        // Resolved once per render rather than per row — the same lookup that survives a metadata
        // re-read, see Bookmark.resolvedStoryIndex.
        let selected = bookmark.resolvedStoryIndex()
        let suggestion = bookmark.suggestedStory()
        let customTitles = bookmark.book?.customStoryTitles ?? []
        return VStack(spacing: 0) {
            // The likely answer first, so the common case is one tap without reading the index.
            if let suggestion {
                pickRow(isSelected: false) {
                    suggestionLabel(suggestion)
                } action: {
                    commit { bookmark.assign(suggestion) }
                }
                Divider().padding(.leading, 30)
            }
            // Clearing sits at the top of the same list rather than in a separate destructive
            // button: "no story" is one of the choices, not a different kind of action.
            pickRow(isSelected: !bookmark.hasStory) {
                plainLabel(Text("No Story"))
            } action: {
                commit { bookmark.clearStory() }
            }
            ForEach(Array(stories.enumerated()), id: \.offset) { index, story in
                Divider().padding(.leading, 30)
                pickRow(isSelected: index == selected) {
                    StoryRow(story: story)
                } action: {
                    commit { bookmark.assignStory(at: index) }
                }
            }
            // Names typed by hand for this comic, so the next page of the same story can join it.
            ForEach(customTitles, id: \.self) { title in
                Divider().padding(.leading, 30)
                pickRow(isSelected: selected == nil && bookmark.storyLabel == title) {
                    plainLabel(Text(verbatim: title))
                } action: {
                    commit { bookmark.assignCustomStory(title) }
                }
            }
            Divider().padding(.leading, 30)
            newStoryRow
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func suggestionLabel(_ suggestion: Bookmark.StorySuggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Suggested", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(verbatim: suggestion.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let other = suggestion.otherPage {
                    Text("Same as pages \(suggestion.page + 1) and \(other + 1)")
                } else {
                    Text("Same as page \(suggestion.page + 1)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 38)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// A row that is only a title, inset to line up with the index rows' titles below the number.
    private func plainLabel(_ text: Text) -> some View {
        text
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 38)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
    }

    /// "New Story…", which becomes a name field in place. Return commits, an empty name does
    /// nothing.
    @ViewBuilder private var newStoryRow: some View {
        if isNaming {
            HStack(spacing: 8) {
                TextField("Story Name", text: $newName)
                    .font(.callout.weight(.medium))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(saveNewName)
                Button("Save", action: saveNewName)
                    .font(.callout.weight(.semibold))
                    .disabled(newName.nonEmpty == nil)
            }
            .padding(.leading, 38)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .onAppear { nameFocused = true }
        } else {
            Button {
                isNaming = true
            } label: {
                Label("New Story…", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func saveNewName() {
        guard newName.nonEmpty != nil else { return }
        commit { bookmark.assignCustomStory(newName) }
    }

    /// One choosable row. The tick is always laid out (hidden, not absent) so picking a different
    /// story can't reflow the list under the finger.
    private func pickRow<Content: View>(isSelected: Bool,
                                        @ViewBuilder content: () -> Content,
                                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                content()
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.trailing, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Picking commits and closes: there's one outcome and nothing to confirm, the same way the
    /// reader's page grid jumps and dismisses on a tap.
    private func commit(_ change: () -> Void) {
        change()
        try? context.save()
        dismiss()
    }
}

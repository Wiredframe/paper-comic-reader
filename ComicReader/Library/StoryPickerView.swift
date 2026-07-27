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

    /// Which page this is about. The sheet is opened from four places and none of them stays on
    /// screen behind it, so it has to name the page itself.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bookmark.book?.displayTitle ?? "—")
                .font(.headline)
                .lineLimit(1)
            Text(bookmark.pageLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var list: some View {
        // Resolved once per render rather than per row — the same lookup that survives a metadata
        // re-read, see Bookmark.resolvedStoryIndex.
        let selected = bookmark.resolvedStoryIndex()
        return VStack(spacing: 0) {
            // Clearing sits at the top of the same list rather than in a separate destructive
            // button: "no story" is one of the choices, not a different kind of action.
            pickRow(isSelected: !bookmark.hasStory) {
                Text("No Story")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 12)
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
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

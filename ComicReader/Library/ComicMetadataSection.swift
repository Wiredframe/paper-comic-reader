//
//  ComicMetadataSection.swift
//  Comic Reader
//
//  What a comic's ComicInfo.xml says, laid out. Deliberately NOT a screen: it brings no
//  ScrollView and no navigation, so it can be dropped into either presentation —
//
//    · inline, under the bookmarks on the Discover carousel's second page
//    · inside ComicDetailView, the sheet the grid, the list and the reader present
//
//  — and the two can't drift apart, because there is only one of it.
//
//  The star is the story list: ComicInfo has no field for "what's inside this issue", so
//  taggers write the index into <Summary> and ComicInfoParser lifts it back out. When it
//  couldn't be parsed, `summary` renders as the block of text it is, and nothing is lost.
//

import SwiftUI

struct ComicMetadataSection: View {
    let book: ComicBook
    /// The carousel needs the heading (the panel naming this comic is a screen above by the
    /// time you get here); the sheet doesn't (its own header just said it).
    var showsHeading: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsHeading { heading }

            if !book.stories.isEmpty {
                storyList
            } else if let summary = book.summary?.nonEmpty {
                block("Summary", text: summary)
            }

            // With a story list these say the same thing the per-story credits do, only
            // without saying who did what — so they'd be a worse duplicate.
            if book.stories.isEmpty { credits }

            if let characters = book.characters?.nonEmpty {
                block("Characters", text: characters)
            }

            publication
        }
    }

    // MARK: Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Details")
                .font(.title3.weight(.semibold))
            Text(book.displayTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Stories

    private var storyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(book.storyCountLabel ?? "Stories")
            VStack(spacing: 0) {
                ForEach(Array(book.stories.enumerated()), id: \.element.id) { index, story in
                    if index > 0 { Divider().padding(.leading, 30) }
                    StoryRow(story: story)
                }
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Credits (only without a story list)

    @ViewBuilder private var credits: some View {
        let roles: [(String, String)] = [
            ("Writer", book.writers), ("Penciller", book.pencillers), ("Inker", book.inkers)
        ].compactMap { role, names in names?.nonEmpty.map { (role, $0) } }

        if !roles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Credits")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(roles, id: \.0) { role, names in
                        LabeledField(label: role, value: names)
                    }
                }
            }
        }
    }

    // MARK: Publication

    @ViewBuilder private var publication: some View {
        let fields: [(String, String)] = [
            ("Publisher", book.publisher?.nonEmpty),
            ("Published", book.dateLabel),
            ("Language", languageName),
        ].compactMap { label, value in value.map { (label, $0) } }

        if !fields.isEmpty || book.webURL?.nonEmpty != nil || book.notes?.nonEmpty != nil {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Publication")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(fields, id: \.0) { label, value in
                        LabeledField(label: label, value: value)
                    }
                    if let web = book.webURL?.nonEmpty, let url = URL(string: web) {
                        Link(destination: url) {
                            Label("More about this issue", systemImage: "safari")
                                .font(.subheadline)
                        }
                        .padding(.top, 2)
                    }
                }
                // Provenance, in the smallest type on the page: it says where the facts above
                // came from, which matters exactly when you doubt one of them.
                if let notes = book.notes?.nonEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// "Italian" rather than "it" — the ISO code is for machines.
    private var languageName: String? {
        guard let code = book.languageISO?.nonEmpty else { return nil }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func block(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

/// One entry from the issue's index. The title leads, because that's what you're scanning
/// for; the credits sit under it in the tone of a caption.
private struct StoryRow: View {
    let story: ComicStory

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(story.number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                Text(story.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if !story.credits.isEmpty {
                    Text(creditsLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            // The tagger's own word for what this is — "Storia", "Copertina", "Cover". Shown
            // only when it isn't the obvious one: in a list of stories, "Storia" on every row
            // is noise, while the one cover among them is worth marking.
            if let kind = story.kind.nonEmpty, !Self.isPlainStory(kind) {
                Text(kind)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// Roles collapse when one person did several jobs: "Mario Volta" once, not
    /// "Soggetto: Mario Volta · Sceneggiatura: Mario Volta". Order is the tagger's.
    private var creditsLine: String {
        var names: [String] = []
        var rolesByName: [String: [String]] = [:]
        for credit in story.credits {
            if rolesByName[credit.name] == nil { names.append(credit.name) }
            rolesByName[credit.name, default: []].append(credit.role)
        }
        return names
            .map { name in "\((rolesByName[name] ?? []).joined(separator: ", ")): \(name)" }
            .joined(separator: "  ·  ")
    }

    /// The default kind, in the languages the taggers we've seen write. Anything unrecognised
    /// gets a badge — better a redundant one than a silently hidden "Text article".
    private static func isPlainStory(_ kind: String) -> Bool {
        ["storia", "story", "geschichte", "histoire", "historia"].contains(kind.lowercased())
    }
}

/// A "Publisher: Mondadori" line — label and value on one baseline, wrapping as a unit.
private struct LabeledField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

//
//  ComicInfo.swift
//  Comic Reader
//
//  Reads the ComicInfo.xml that comic archives carry by convention (the ComicRack
//  schema, which every tagger writes) into plain values. Parsed once at import and
//  stored on the ComicBook — no view ever touches XML.
//
//  The interesting part is `stories`. ComicInfo has no field for "what's inside this
//  issue", so taggers put the index in <Summary> as free text. That text is regular
//  enough to parse into rows, and a story list is the whole reason an anthology issue
//  (Topolino, Mickey Mouse Weekly, an annual) is worth opening a detail view for. When
//  the text doesn't match, `stories` is empty and callers fall back to `summary` —
//  nothing is ever lost, it just renders as a block instead of a list.
//

import Foundation

extension String {
    /// The string, or nil when it's blank. Taggers write empty elements (`<Series/>`) and
    /// whitespace-only ones freely, and " " is not metadata — this keeps every "do we have
    /// this field?" check from having to say so twice.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One entry from the index in `<Summary>` — a story, a cover, a text piece.
struct ComicStory: Codable, Hashable, Identifiable, Sendable {
    /// Position in the index (1-based, as printed). Unique within an issue, so it doubles
    /// as the `ForEach` identity.
    let number: Int
    /// Whatever the tagger called it — "Storia", "Copertina", "Story", "Cover". Shown
    /// verbatim as a badge rather than mapped to an enum: the label is localised by the
    /// tool that wrote it, and guessing at translations would only ever be wrong.
    let kind: String
    let title: String
    /// The INDUCKS-style story code, e.g. "I TL 1900-A".
    let code: String?
    let credits: [Credit]

    var id: Int { number }

    struct Credit: Codable, Hashable, Sendable {
        let role: String    // "Disegni", "Sceneggiatura", "Script", …
        let name: String
    }
}

/// The fields we lift out of ComicInfo.xml. All optional — a comic may carry none, some
/// or all of them.
struct ComicInfoData: Sendable {
    var series: String?
    var number: String?
    var title: String?
    var summary: String?
    var publisher: String?
    var year: Int?
    var month: Int?
    var day: Int?
    var writer: String?
    var penciller: String?
    var inker: String?
    var characters: String?
    var languageISO: String?
    var web: String?
    var notes: String?
    var stories: [ComicStory] = []

    /// True when there's anything worth showing. A file with a ComicInfo.xml that holds
    /// only, say, a PageCount shouldn't light up the detail view.
    var isEmpty: Bool {
        series == nil && number == nil && title == nil && summary == nil
            && publisher == nil && year == nil && writer == nil && penciller == nil
            && inker == nil && characters == nil && web == nil && stories.isEmpty
    }
}

enum ComicInfoParser {

    /// Parses ComicInfo.xml bytes. Returns nil if the data isn't the expected document or
    /// carries nothing useful.
    static func parse(_ data: Data) -> ComicInfoData? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        var info = ComicInfoData()
        let fields = delegate.fields
        info.series = fields["Series"]
        info.number = fields["Number"]
        info.title = fields["Title"]
        info.summary = fields["Summary"]
        info.publisher = fields["Publisher"]
        info.year = fields["Year"].flatMap(Int.init)
        info.month = fields["Month"].flatMap(Int.init)
        info.day = fields["Day"].flatMap(Int.init)
        info.writer = fields["Writer"]
        info.penciller = fields["Penciller"]
        info.inker = fields["Inker"]
        info.characters = fields["Characters"]
        info.languageISO = fields["LanguageISO"]
        info.web = fields["Web"]
        info.notes = fields["Notes"]
        info.stories = info.summary.map(stories(fromSummary:)) ?? []

        return info.isEmpty ? nil : info
    }

    // MARK: Summary → stories

    /// Matches an index entry line:
    ///
    ///     2. [Storia] «Paperino e l'amaca della felicità»  {I TL 1900-A}
    ///
    /// The kind, the code and the closing guillemet are all optional, so a tagger that
    /// writes only `3. «Title»` still parses. Anything that doesn't match at all is left
    /// to the raw-summary fallback.
    private static let entryPattern = try? NSRegularExpression(
        pattern: #"^\s*(\d+)\.\s*(?:\[([^\]]*)\]\s*)?[«"](.+?)[»"]\s*(?:\{([^}]*)\})?\s*$"#)

    /// Matches a credits line following an entry — `Disegni: X · Chine: Y`, or with the
    /// roles separated by the middle dot the taggers use.
    private static let creditSeparator = CharacterSet(charactersIn: "·•")

    static func stories(fromSummary summary: String) -> [ComicStory] {
        guard let entryPattern else { return [] }

        var stories: [ComicStory] = []
        for rawLine in summary.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = entryPattern.firstMatch(in: line, range: range) {
                let number = Int(capture(1, of: match, in: line) ?? "") ?? stories.count + 1
                let kind = capture(2, of: match, in: line) ?? ""
                let title = capture(3, of: match, in: line) ?? ""
                let code = capture(4, of: match, in: line)
                stories.append(ComicStory(number: number, kind: kind, title: title,
                                          code: code, credits: []))
            } else if !stories.isEmpty,
                      let credits = credits(from: line, indented: rawLine.first?.isWhitespace == true),
                      !credits.isEmpty {
                // A credits line belongs to the entry above it.
                let last = stories.removeLast()
                stories.append(ComicStory(number: last.number, kind: last.kind, title: last.title,
                                          code: last.code, credits: last.credits + credits))
            }
        }
        return stories
    }

    /// Splits `Soggetto: A · Sceneggiatura: B` into roles and names, or returns nil when the
    /// line isn't credits at all.
    ///
    /// Three guards, because prose is full of colons and a bogus "Note → reprinted in 1995"
    /// row would read as fact: every segment must carry a colon, a role has to be short
    /// enough to be a label rather than a sentence, and the line must either be indented
    /// under its entry (how an index block is written) or list several roles at once. A
    /// trailing "Note: …" paragraph satisfies none of them.
    private static func credits(from line: String, indented: Bool) -> [ComicStory.Credit]? {
        let segments = line.components(separatedBy: creditSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty, indented || segments.count > 1 else { return nil }

        var credits: [ComicStory.Credit] = []
        for segment in segments {
            guard let colon = segment.firstIndex(of: ":") else { return nil }
            let role = String(segment[segment.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let name = String(segment[segment.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !role.isEmpty, !name.isEmpty, role.count <= 24 else { return nil }
            credits.append(ComicStory.Credit(role: role, name: name))
        }
        return credits
    }

    private static func capture(_ index: Int, of match: NSTextCheckingResult,
                                in line: String) -> String? {
        guard let range = Range(match.range(at: index), in: line) else { return nil }
        let value = String(line[range]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: XMLParser glue

    /// Collects the text of ComicInfo's direct children. Depth-limited on purpose: the
    /// `<Pages><Page …/></Pages>` block nests, and its children must not land in the same
    /// flat bag as <Title>.
    private final class Delegate: NSObject, XMLParserDelegate {
        var fields: [String: String] = [:]

        private var depth = 0
        private var current: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            depth += 1
            if depth == 2 {
                current = element
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard current != nil else { return }
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String,
                    namespaceURI: String?, qualifiedName: String?) {
            if depth == 2, let current {
                // Trim only the edges: <Summary> is multi-line and its internal newlines
                // are the index's layout.
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { fields[current] = value }
                self.current = nil
                text = ""
            }
            depth -= 1
        }
    }
}

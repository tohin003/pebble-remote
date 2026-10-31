import Foundation
import SwiftUI

/// A reply split into Markdown blocks. SwiftUI's `Text` renders inline Markdown (bold, italic, code, links) but not
/// blocks, so blocks are split here and each renders as its own view. Tolerant of a reply that is still streaming: an
/// unclosed code fence is a code block that is still open.
nonisolated enum MarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    /// `marker` is "•" or "3."; `depth` counts indentation steps.
    case listItem(marker: String, text: String, depth: Int)
    case quote(String)
    case code(language: String?, text: String, closed: Bool)
    case rule
}

nonisolated public enum MarkdownBlocks {
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: (fence: String, language: String?, lines: [String])?

        func flush() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).replacingOccurrences(of: "\r", with: "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let open = code {
                if trimmed.hasPrefix(open.fence) && trimmed.trimmingCharacters(in: CharacterSet(charactersIn: open.fence.prefix(1).description)).isEmpty {
                    blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"), closed: true))
                    code = nil
                } else {
                    code?.lines.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fenceChar = trimmed.first!
                let fence = String(trimmed.prefix { $0 == fenceChar })
                let info = trimmed.dropFirst(fence.count).trimmingCharacters(in: .whitespaces)
                code = (fence, info.isEmpty ? nil : info, [])
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let heading = headingMatch(trimmed) {
                flush()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if isRule(trimmed) {
                flush()
                blocks.append(.rule)
                continue
            }
            if let item = listMatch(line) {
                flush()
                blocks.append(.listItem(marker: item.marker, text: item.text, depth: item.depth))
                continue
            }
            if trimmed.hasPrefix(">") {
                flush()
                let text = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if case .quote(let previous) = blocks.last {
                    blocks[blocks.count - 1] = .quote(previous + "\n" + text)
                } else {
                    blocks.append(.quote(text))
                }
                continue
            }
            paragraph.append(line)
        }
        if let open = code {
            blocks.append(.code(language: open.language, text: open.lines.joined(separator: "\n"), closed: false))
        }
        flush()
        return blocks
    }

    static func headingMatch(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        return (hashes, text)
    }

    static func isRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func listMatch(_ line: String) -> (marker: String, text: String, depth: Int)? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let depth = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        let body = line.dropFirst(indent.count)
        if let first = body.first, "-*+".contains(first), body.dropFirst().first == " " {
            return ("•", body.dropFirst(2).trimmingCharacters(in: .whitespaces), min(depth, 4))
        }
        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let after = body.dropFirst(digits.count)
            if let mark = after.first, mark == "." || mark == ")", after.dropFirst().first == " " {
                return ("\(digits).", after.dropFirst(2).trimmingCharacters(in: .whitespaces), min(depth, 4))
            }
        }
        return nil
    }

    /// Inline Markdown (bold, italic, code spans, links) as an attributed string, with code spans set in Pebble's
    /// code font and colour. Anything that fails to parse shows as plain text. With `citations`, Pebble's source markers
    /// become links (`linkCitations`).
    static func inline(
        _ text: String, codeFont: AttributeContainer = AttributeContainer(), citations: Bool = false
    ) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        var attributed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        for run in attributed.runs where run.inlinePresentationIntent?.contains(.code) == true {
            attributed[run.range].mergeAttributes(codeFont)
        }
        if citations, text.contains("[S") { linkCitations(&attributed) }
        return attributed
    }

    // MARK: Source markers

    /// The scheme of a source marker's link; the conversation opens it (`sourceID(of:)`), nothing else does.
    public static let sourceScheme = "pebble-source"

    /// The id a source marker's link names ("S7"), or nil for any other link.
    public static func sourceID(of url: URL) -> String? {
        guard url.scheme == sourceScheme else { return nil }
        let id = url.absoluteString.dropFirst(sourceScheme.count + 1)
        let marker = citationMarkers(in: "[\(id)]")
        return marker.count == 1 && marker[0].ids.count == 1 ? String(id) : nil
    }

    /// Pebble's source markers ("[S7]", "[S1, S3]": Markdown.vue's `citations`) as links, one per id, in the chip's
    /// font; the brackets and commas go, as on the Mac. Text in code spans and in links keeps its words.
    static func linkCitations(_ attributed: inout AttributedString) {
        var found: [(range: Range<AttributedString.Index>, ids: [String])] = []
        for run in attributed.runs where run.link == nil && run.inlinePresentationIntent?.contains(.code) != true {
            let text = String(attributed[run.range].characters)
            for marker in citationMarkers(in: text) {
                let lower = attributed.characters.index(run.range.lowerBound, offsetBy: marker.offset)
                let upper = attributed.characters.index(lower, offsetBy: marker.length)
                found.append((lower..<upper, marker.ids))
            }
        }
        // From the end, so the ranges still to replace keep their places.
        for marker in found.reversed() {
            let attributes = attributed[marker.range].runs.first?.attributes ?? AttributeContainer()
            var replacement = AttributedString()
            for (index, id) in marker.ids.enumerated() {
                if index > 0 { replacement += AttributedString(" ", attributes: attributes) }
                var chip = AttributedString(id, attributes: attributes)
                chip.link = URL(string: "\(sourceScheme):\(id)")
                chip.font = PebbleFont.chip
                replacement += chip
            }
            attributed.replaceSubrange(marker.range, with: replacement)
        }
    }

    /// Each source marker in `text`: where it starts and how long it is, in characters, and its ids. A marker is "[",
    /// one to six ids ("S", a digit 1 to 9, up to two more digits) with commas between them (spaces allowed around a
    /// comma), then "]".
    static func citationMarkers(in text: String) -> [(offset: Int, length: Int, ids: [String])] {
        let characters = Array(text)
        var found: [(offset: Int, length: Int, ids: [String])] = []
        var start = 0
        while start < characters.count {
            if characters[start] == "[", let marker = citationMarker(characters, at: start) {
                found.append((start, marker.length, marker.ids))
                start += marker.length
            } else {
                start += 1
            }
        }
        return found
    }

    private static func citationMarker(_ characters: [Character], at open: Int) -> (length: Int, ids: [String])? {
        func isDigit(_ index: Int) -> Bool {
            index < characters.count && characters[index].isASCII && characters[index].isWholeNumber
        }
        func skipSpaces(_ index: inout Int) {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
        }
        var ids: [String] = []
        var at = open + 1
        while ids.count < 6 {
            guard at < characters.count, characters[at] == "S", isDigit(at + 1), characters[at + 1] != "0" else {
                return nil
            }
            var end = at + 2
            while end - at < 4, isDigit(end) { end += 1 }
            ids.append(String(characters[at..<end]))
            if end < characters.count, characters[end] == "]" { return (end + 1 - open, ids) }
            at = end
            skipSpaces(&at)
            guard at < characters.count, characters[at] == "," else { return nil }
            at += 1
            skipSpaces(&at)
        }
        return nil
    }
}

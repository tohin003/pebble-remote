import Foundation

/// A conversation's newest message as one short line, for the preview of a long press on Chats (lane Z, U-19): who
/// wrote it and its words without Markdown's marks. Never the transcript itself.
public struct ChatLastLine: Sendable, Hashable {
    /// The person wrote it (otherwise it is Pebble's reply).
    public var fromPerson: Bool
    public var text: String

    public init(fromPerson: Bool, text: String) {
        self.fromPerson = fromPerson
        self.text = text
    }

    /// The most characters a line keeps.
    public static let limit = 160

    /// A message as a line, or nil when no words are left (an empty reply, a lone code fence).
    public static func make(role: MessageItem.Role, text: String) -> ChatLastLine? {
        plain(text).map { ChatLastLine(fromPerson: role == .user, text: $0) }
    }

    /// The words of a Markdown message on one line: code fences, heading, quote and list marks and inline Markdown
    /// (bold, code spans, links: their text) taken out; control and direction characters removed and runs of spaces
    /// folded (`PebbleWorld.clean`); at most `limit` characters, ending in "…" when cut.
    public static func plain(_ markdown: String) -> String? {
        var lines: [String] = []
        for raw in markdown.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { continue }
            let words = withoutBlockMark(line)
            if !words.isEmpty { lines.append(words) }
        }
        let joined = lines.joined(separator: " ")
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        let inline = (try? AttributedString(markdown: joined, options: options)).map { String($0.characters) } ?? joined
        return PebbleWorld.clean(inline, limit: limit)
    }

    /// A line without the mark that starts a Markdown block: "## ", "> ", "- ", "* ", "+ ", "3. ", "3) ".
    static func withoutBlockMark(_ line: String) -> String {
        var rest = Substring(line)
        let hashes = rest.prefix { $0 == "#" }.count
        let digits = rest.prefix { $0.isASCII && $0.isNumber }.count
        if (1...6).contains(hashes), rest.dropFirst(hashes).first == " " {
            rest = rest.dropFirst(hashes)
        } else if rest.first == ">" {
            rest = rest.dropFirst()
        } else if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            rest = rest.dropFirst(2)
        } else if (1...9).contains(digits), let mark = rest.dropFirst(digits).first, mark == "." || mark == ")",
            rest.dropFirst(digits + 1).first == " "
        {
            rest = rest.dropFirst(digits + 2)
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}

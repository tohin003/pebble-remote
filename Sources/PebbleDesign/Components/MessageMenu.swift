import Foundation

/// What a long press on a message offers (lane Z, item 2): the Mac's message actions (MessageActions.vue) that the phone
/// can do, chosen by the transcript for each message and drawn by `MessageBubble` as its context menu.
/// - Copy, always, on the phone (the person's words as sent, or the reply's Markdown).
/// - Copy Code for each code block of a reply (Markdown.vue's "Copy code").
/// - Open Link for each web link, on this iPhone, never on the Mac (F13).
/// - Edit (the person's last message) and Retry (the latest reply), each a new message; Retry unavailable with Pebble's
///   reason when the question had attachments.
nonisolated public struct MessageMenu {
    nonisolated public enum Item: Hashable, Sendable {
        case copy
        case copyCode(String)
        case openLink(URL)
        case edit
        case retry
        /// Retry can't run; Pebble's reason.
        case retryUnavailable(String)
    }

    public var items: [Item]
    public var perform: (Item) -> Void

    public init(items: [Item], perform: @escaping (Item) -> Void) {
        self.items = items
        self.perform = perform
    }

    /// The most code blocks and links a menu lists; a reply with more keeps them on the page.
    public static let most = 6

    /// The text of each code block in a Markdown message, in order, empty ones left out.
    public static func codeBlocks(in markdown: String) -> [String] {
        let blocks = MarkdownBlocks.parse(markdown).compactMap { block -> String? in
            guard case .code(_, let text, _) = block, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        return Array(blocks.prefix(most))
    }

    /// The web links in a message, in order and each once: its Markdown links, as the bubble shows them, then the
    /// addresses written out in the words it shows (code blocks left out). Only `http` and `https` with a host; the
    /// screen decides what opens.
    public static func links(in markdown: String) -> [URL] {
        var found: [URL] = []
        func keep(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil,
                !found.contains(url)
            else { return }
            found.append(url)
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for block in MarkdownBlocks.parse(markdown) {
            let text: String
            switch block {
            case .paragraph(let words), .heading(_, let words), .listItem(_, let words, _), .quote(let words): text = words
            case .code, .rule: continue
            }
            let shown = MarkdownBlocks.inline(text)
            for run in shown.runs {
                if let url = run.link { keep(url) }
            }
            // The words as the bubble shows them: a Markdown link's address is not among them, only its text.
            let words = String(shown.characters)
            for match in detector?.matches(in: words, range: NSRange(words.startIndex..., in: words)) ?? [] {
                if let url = match.url { keep(url) }
            }
        }
        return Array(found.prefix(most))
    }

    /// A code block's first line, for its menu item.
    public static func firstLine(_ code: String) -> String {
        let line = code.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 40 ? String(trimmed.prefix(39)) + "\u{2026}" : trimmed
    }

    /// A link as its menu item names it: the host and as much of the path as fits.
    public static func linkName(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let shown = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = url.path(percentEncoded: false)
        let named = path.isEmpty || path == "/" ? shown : shown + path
        return named.count > 40 ? String(named.prefix(39)) + "\u{2026}" : named
    }
}

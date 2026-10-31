import Foundation
import Testing

@testable import PebbleDesign

/// Pebble's replies split into blocks, including while they stream.
struct MarkdownBlocksTests {
    @Test func paragraphsHeadingsListsQuotesAndRules() {
        let blocks = MarkdownBlocks.parse(
            """
            ## What I found
            The test reads `TZ`.
            It fails on CI.

            - first
              - nested
            3. third
            > quoted
            > more
            ---
            """)
        #expect(
            blocks == [
                .heading(level: 2, text: "What I found"),
                .paragraph("The test reads `TZ`.\nIt fails on CI."),
                .listItem(marker: "•", text: "first", depth: 0),
                .listItem(marker: "•", text: "nested", depth: 1),
                .listItem(marker: "3.", text: "third", depth: 0),
                .quote("quoted\nmore"),
                .rule,
            ])
    }

    @Test func codeFencesOpenAndClosed() {
        #expect(
            MarkdownBlocks.parse("```ts\nlet a = 1\n\nlet b = 2\n```\nafter")
                == [.code(language: "ts", text: "let a = 1\n\nlet b = 2", closed: true), .paragraph("after")])
        // still streaming: the fence is open
        #expect(MarkdownBlocks.parse("Here:\n```\nnpm te") == [.paragraph("Here:"), .code(language: nil, text: "npm te", closed: false)])
        #expect(MarkdownBlocks.parse("~~~~\na\n~~~\nb\n~~~~") == [.code(language: nil, text: "a\n~~~\nb", closed: true)])
    }

    @Test func notEverythingWithAMarkIsABlock() {
        #expect(MarkdownBlocks.parse("#hashtag") == [.paragraph("#hashtag")])
        #expect(MarkdownBlocks.parse("-not a list") == [.paragraph("-not a list")])
        #expect(MarkdownBlocks.parse("2024. A year") == [.listItem(marker: "2024.", text: "A year", depth: 0)])
        #expect(MarkdownBlocks.parse("") == [])
    }

    @Test func inlineMarkdownKeepsTheWordsAndMarksCode() {
        let attributed = MarkdownBlocks.inline("Run `npm test` **now**")
        #expect(String(attributed.characters) == "Run npm test now")
        let coded = attributed.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }
        #expect(coded.count == 1)
        #expect(String(attributed.characters[coded[0].range]) == "npm test")
        // unparseable input still shows
        #expect(String(MarkdownBlocks.inline("a [b](").characters).contains("a"))
    }

    /// TR-10, Markdown.vue's `citations`: each id of a source marker is a link the conversation opens; the brackets and
    /// commas go. Code and links keep their words, and anything else in brackets stays text.
    @Test func sourceMarkersBecomeOneLinkPerID() {
        func links(_ text: String) -> [(words: String, link: String)] {
            let attributed = MarkdownBlocks.inline(text, citations: true)
            return attributed.runs.compactMap { run in
                run.link.map { (String(attributed.characters[run.range]), $0.absoluteString) }
            }
        }
        let one = MarkdownBlocks.inline("Sunny, 24 °C [S1].", citations: true)
        #expect(String(one.characters) == "Sunny, 24 °C S1.")
        #expect(links("Sunny, 24 °C [S1].").map(\.link) == ["pebble-source:S1"])
        let pair = links("Then sun [S1, S2] and [S12 ,S7]")
        #expect(pair.map(\.words) == ["S1", "S2", "S12", "S7"])
        #expect(pair.map(\.link) == ["pebble-source:S1", "pebble-source:S2", "pebble-source:S12", "pebble-source:S7"])
        // code, a link's own words, and what isn't a marker
        #expect(links("Use `[S2]` here").isEmpty)
        #expect(links("[S4](https://example.com)").map(\.link) == ["https://example.com"])
        for text in ["[S0]", "[S1234]", "[S1 ]", "[s1]", "[S1,]", "[S1, S2, S3, S4, S5, S6, S7]", "[Sources]"] {
            #expect(links(text).isEmpty, "\(text)")
        }
        #expect(links("[S1, S2, S3, S4, S5, S6]").count == 6)
        // only where asked: a person's message, or a reply without a run to ask, keeps "[S1]"
        #expect(String(MarkdownBlocks.inline("see [S1]").characters) == "see [S1]")
    }

    @Test func aSourceLinkNamesItsIDAndNothingElseDoes() throws {
        #expect(MarkdownBlocks.sourceID(of: try #require(URL(string: "pebble-source:S7"))) == "S7")
        for text in ["pebble-source:S0", "pebble-source:S1,S2", "pebble-source:S1]", "https://example.com/S1"] {
            #expect(MarkdownBlocks.sourceID(of: try #require(URL(string: text))) == nil, "\(text)")
        }
    }
}

import SwiftUI

/// One message in a conversation, as Pebble shows it: your messages in a soft sage bubble on the trailing side (the
/// small corner at the bottom, toward you), Pebble's replies as plain text on the page with Markdown: paragraphs,
/// headings, lists, quotes, code blocks (scrolling sideways, never wrapped), inline code and links.
///
/// While Pebble is still writing, a caret follows the last word (it blinks at 1 Hz; still under Reduce Motion), drawn
/// beside the text so VoiceOver never reads it; VoiceOver hears "Pebble is still writing" instead.
///
/// A long press opens the message's menu when the transcript gives it one (`MessageMenu`: Copy, Copy Code, its links,
/// Edit or Retry), lifted in the bubble's own shape; the text is selectable only where there is no menu, so the two
/// never fight over the long press. Content layer: no glass.
public struct MessageBubble: View {
    public enum Role: Hashable, Sendable { case person, pebble }

    let role: Role
    let text: String
    let isStreaming: Bool
    let menu: MessageMenu?
    /// Pebble's source markers ([S7]) in a reply become links the conversation opens (`MarkdownBlocks.sourceID`).
    let citesSources: Bool

    public init(
        role: Role, text: String, isStreaming: Bool = false, menu: MessageMenu? = nil, citesSources: Bool = false
    ) {
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.menu = menu
        self.citesSources = citesSources
    }

    public var body: some View {
        switch role {
        case .person:
            HStack {
                Spacer(minLength: PebbleSpace.s6 + PebbleSpace.s4)
                Text(MarkdownBlocks.inline(text, codeFont: codeAttributes))
                    .font(PebbleFont.message)
                    .foregroundStyle(PebbleColor.text)
                    .selectable(menu == nil)
                    .padding(.horizontal, PebbleSpace.s4)
                    .padding(.vertical, PebbleSpace.s3 - 2)
                    .background(PebbleColor.userBubble, in: PebbleShapes.personBubble)
                    .messageMenu(menu, role: role, preview: PebbleShapes.personBubble)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: AppCopy.Accessibility.fromYou(text)))
        case .pebble:
            // The reply sits on the page without a bubble: its preview gets a little room around the words.
            let preview = RoundedRectangle(cornerRadius: PebbleRadius.md).inset(by: -PebbleSpace.s2)
            MarkdownText(text: text, isStreaming: isStreaming, selectable: menu == nil, citations: citesSources)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Lifted for its menu, the words need the page under them, or they lie over the dimmed transcript and
                // the title (the re-check's U-60): the page's own colour in the preview's shape, which can't be seen
                // in the transcript. The transcript keeps more than the shape's 8 pt between rows.
                .background(.background, in: preview)
                .messageMenu(menu, role: role, preview: preview)
                .accessibilityElement(children: .combine)
                .accessibilityValue(isStreaming ? AppCopy.Conversation.stillWriting : "")
        }
    }

    private var codeAttributes: AttributeContainer {
        var container = AttributeContainer()
        container.font = PebbleFont.code
        container.backgroundColor = PebbleColor.code
        return container
    }
}

/// Pebble's reply as Markdown blocks. Parsing happens once per text change; only the last block redraws while the
/// caret blinks.
struct MarkdownText: View {
    let text: String
    let isStreaming: Bool
    /// The text is selectable (a message without a menu).
    var selectable = true
    /// Source markers ([S7]) become links (`MarkdownBlocks.linkCitations`).
    var citations = false

    var body: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            ForEach(blocks.enumerated(), id: \.offset) { index, block in
                MarkdownBlockView(block: block, caret: isStreaming && index == blocks.count - 1, citations: citations)
            }
            if isStreaming && blocks.isEmpty {
                MarkdownBlockView(block: .paragraph(""), caret: true)
            }
        }
        .selectable(selectable)
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let caret: Bool
    var citations = false

    var body: some View {
        switch block {
        case .paragraph(let text):
            CaretText(attributed: MarkdownBlocks.inline(text, codeFont: Self.code, citations: citations), font: PebbleFont.message, caret: caret)
                .foregroundStyle(PebbleColor.text)
        case .heading(let level, let text):
            CaretText(
                attributed: MarkdownBlocks.inline(text, codeFont: Self.code, citations: citations),
                font: level <= 1 ? PebbleFont.title : PebbleFont.messageHeading, caret: caret
            )
            .foregroundStyle(PebbleColor.text)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, PebbleSpace.s1)
        case .listItem(let marker, let text, let depth):
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                Text(verbatim: marker)
                    .font(PebbleFont.message.monospacedDigit())
                    .foregroundStyle(PebbleColor.secondaryText)
                    .accessibilityHidden(marker == "•")
                CaretText(attributed: MarkdownBlocks.inline(text, codeFont: Self.code, citations: citations), font: PebbleFont.message, caret: caret)
                    .foregroundStyle(PebbleColor.text)
            }
            .padding(.leading, CGFloat(depth) * PebbleSpace.s4)
        case .quote(let text):
            HStack(spacing: PebbleSpace.s3) {
                Capsule()
                    .fill(PebbleColor.accentSoft)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                CaretText(attributed: MarkdownBlocks.inline(text, codeFont: Self.code, citations: citations), font: PebbleFont.message, caret: caret)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text, _):
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                if let language {
                    Text(verbatim: language)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.mutedText)
                }
                // Long lines scroll sideways inside the block, never the transcript. The block starts at its lines'
                // beginning: the transcript's own anchor (its bottom, centred across) would otherwise reach in here.
                ScrollView(.horizontal) {
                    CaretText(attributed: AttributedString(text), font: PebbleFont.code, caret: caret)
                        .foregroundStyle(PebbleColor.text)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .defaultScrollAnchor(.topLeading)
                .scrollIndicators(.hidden)
            }
            .padding(PebbleSpace.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PebbleColor.code, in: .rect(cornerRadius: PebbleRadius.md))
            .overlay { RoundedRectangle(cornerRadius: PebbleRadius.md).stroke(PebbleColor.line, lineWidth: 1) }
        case .rule:
            Divider().overlay(PebbleColor.line)
        }
    }

    private static var code: AttributeContainer {
        var container = AttributeContainer()
        container.font = PebbleFont.code
        container.backgroundColor = PebbleColor.code
        return container
    }
}

/// Text with an optional caret after its last glyph, drawn by a `TextRenderer` so it is not part of the string.
struct CaretText: View {
    let attributed: AttributedString
    let font: Font
    let caret: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if caret {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate * 2).isMultiple(of: 2)
                Text(attributed)
                    .font(font)
                    .textRenderer(CaretRenderer(visible: on, color: PebbleColor.accent))
            }
        } else {
            Text(attributed)
                .font(font)
        }
    }
}

/// Draws the text, then a rounded bar just after its last glyph (or at the start of an empty line).
nonisolated struct CaretRenderer: TextRenderer {
    var visible: Bool
    var color: Color

    var displayPadding: EdgeInsets { EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10) }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            ctx.draw(line)
        }
        guard visible else { return }
        var bar: CGRect
        if let line = layout.last {
            let lineBounds = line.typographicBounds.rect
            if let run = line.last {
                let b = run.typographicBounds.rect
                bar = CGRect(x: b.maxX + 2, y: b.minY + b.height * 0.12, width: 3, height: b.height * 0.8)
            } else {
                bar = CGRect(x: lineBounds.minX, y: lineBounds.minY, width: 3, height: max(lineBounds.height, 14))
            }
        } else {
            bar = CGRect(x: 0, y: 0, width: 3, height: 17)
        }
        ctx.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(color))
    }
}

#if os(iOS)
#Preview("Messages") {
    ScrollView {
        VStack(alignment: .leading, spacing: PebbleSpace.s4) {
            MessageBubble(role: .person, text: "Can you fix the login test? It fails on **CI** only.")
            MessageBubble(
                role: .pebble,
                text: """
                    ## What I found
                    The test reads `TZ` from the machine, so it fails on CI.

                    1. Pin the time zone in the test.
                    2. Run the suite again.

                    ```ts
                    process.env.TZ = "UTC";
                    ```
                    > Nothing else changed.
                    """)
            MessageBubble(role: .pebble, text: "Running the tests now", isStreaming: true)
        }
        .padding()
    }
}
#endif

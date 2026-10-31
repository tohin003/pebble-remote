import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// What a card holds, before the person decides (App.vue's card body and ActionReview.vue): an edit's diff ("View
/// diff"), an ad hoc test's check ("View the check"), a command's risk, folder and typed plan, a connector call's
/// arguments, a window's or site's reach, and Pebble's "Technical details". Read-only: the card's own buttons decide.
struct CardDetailsSheet: View {
    let item: ReviewItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let detail = CardDetailCopy.detail(kind: item.kind, payload: item.payload)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PebbleSpace.s3) {
                    Label(ReviewCopy.kindLabel(item.kind), systemImage: PebbleSymbol.card(item.kind))
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.accent)
                    Text(verbatim: item.title)
                        .font(PebbleFont.cardTitle)
                        .foregroundStyle(PebbleColor.text)
                        .accessibilityAddTraits(.isHeader)
                    if let summary = item.summary {
                        Text(summary)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.secondaryText)
                    }
                    if let detail {
                        CardDetailBlocks(blocks: detail.blocks)
                    }
                }
                .padding()
                .frame(maxWidth: PebbleSize.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(detail?.button ?? CardDetailCopy.details)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Common.done) { dismiss() }
                        .pebbleBarButton()
                }
            }
        }
    }
}

/// Pebble's blocks, top to bottom. Values are Pebble's payload, shown as plain text (never as links or instructions).
struct CardDetailBlocks: View {
    let blocks: [CardDetailCopy.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: CardDetailCopy.Block) -> some View {
        switch block {
        case .title(let text):
            Text(verbatim: text)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Self.spoken(text))
        case .text(let text):
            Text(verbatim: text)
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .note(let text):
            Text(verbatim: text)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .alert(let text):
            Label(text, systemImage: "exclamationmark.triangle")
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.danger)
                .fixedSize(horizontal: false, vertical: true)
        case .badges(let badges):
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    Text(verbatim: badge.text)
                        .font(PebbleFont.chip)
                        .foregroundStyle(badge.isAlert ? PebbleColor.danger : PebbleColor.text)
                        .padding(.horizontal, PebbleSpace.s2)
                        .padding(.vertical, PebbleSpace.s1)
                        .background(badge.isAlert ? PebbleColor.hover : PebbleColor.soft, in: .capsule)
                }
            }
        case .why(let reasons):
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                ForEach(Array(reasons.enumerated()), id: \.offset) { _, reason in
                    Label {
                        Text(verbatim: reason).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
                }
            }
        case .label(let text):
            Text(verbatim: text)
                .font(PebbleFont.meta.weight(.semibold))
                .foregroundStyle(PebbleColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .code(let text):
            Text(verbatim: text)
                .font(PebbleFont.cardDetail)
                .foregroundStyle(PebbleColor.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PebbleSpace.s3)
                .background(PebbleColor.code, in: PebbleShapes.inset)
                .overlay { PebbleShapes.inset.stroke(PebbleColor.line, lineWidth: 1) }
        case .diff(let diff):
            Text(Self.colored(diff))
                .font(PebbleFont.cardDetail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PebbleSpace.s3)
                .background(PebbleColor.code, in: PebbleShapes.inset)
                .overlay { PebbleShapes.inset.stroke(PebbleColor.line, lineWidth: 1) }
        case .list(let items):
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                        Text(verbatim: "•").accessibilityHidden(true)
                        Text(verbatim: item)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Self.spoken(item))
                    }
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
                }
            }
        case .facts(let facts):
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: fact.name)
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.mutedText)
                        Text(verbatim: fact.value)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(Self.spoken(fact.value))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        case .technical(let inner):
            DisclosureGroup(CardDetailCopy.technicalDetailsSection) {
                AnyView(CardDetailBlocks(blocks: inner))
                    .padding(.top, PebbleSpace.s2)
            }
            .font(PebbleFont.cardBody)
            .tint(PebbleColor.accent)
        }
    }

    /// What VoiceOver says for a line that may be a bare path: "ThemeToggle.tsx in src/settings".
    static func spoken(_ text: String) -> String { AppCopy.Paths.spoken(text) ?? text }

    /// The diff with Pebble's colours: added lines, removed lines and hunk headers apart (App.vue's `.diff` classes),
    /// and a sign that carries the meaning, never the colour alone.
    static func colored(_ diff: String) -> AttributedString {
        var result = AttributedString()
        let lines = diff.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            var piece = AttributedString(String(line) + (index < lines.count - 1 ? "\n" : ""))
            if line.hasPrefix("+") {
                piece.foregroundColor = PebbleColor.accent
            } else if line.hasPrefix("-") {
                piece.foregroundColor = PebbleColor.danger
            } else if line.hasPrefix("@@") {
                piece.foregroundColor = PebbleColor.mutedText
            } else {
                piece.foregroundColor = PebbleColor.text
            }
            result += piece
        }
        return result
    }
}

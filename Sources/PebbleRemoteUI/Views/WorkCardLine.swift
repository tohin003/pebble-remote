import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A card's one line: its kind's mark, what it did (literal: a command, a Git sentence), the lines a files card
/// changed, its state in words, and in Details when it happened. At the largest text sizes the parts stack.
///
/// In Details › Activity (`showsTime`) the name is never cut to make room for the rest (the re-check's U-46:
/// "Cha…file"). It keeps its one line while it fits beside the diff, the state and the time; when it doesn't, it takes
/// the row's whole width on up to two lines, and they go on a line under it (`ViewThatFits`). The transcript's cards
/// keep their one line, the name giving way in the middle.
struct WorkCardLine: View {
    let card: WorkCard<RunActivityItem>
    let runIsLive: Bool
    let showsTime: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let status = WorkCardWords.status(card, runIsLive: runIsLive)
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Label { name(lines: 3) } icon: { mark }
                    parts(status)
                }
            } else if showsTime {
                ViewThatFits(in: .horizontal) {
                    oneLine(status, keepsName: true)
                    Label {
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            name(lines: 2)
                            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                                parts(status)
                            }
                        }
                    } icon: {
                        mark
                    }
                }
            } else {
                oneLine(status, keepsName: false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The mark and the name, then the diff, the state and the time at the end of the line. `keepsName`: the name
    /// shows whole (Details' first choice, taken only when it fits); otherwise it gives way, cut in the middle.
    private func oneLine(_ status: (words: String, tone: WorkTone)?, keepsName: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
            Label {
                name(lines: 1)
                    .fixedSize(horizontal: keepsName, vertical: false)
            } icon: {
                mark
            }
            Spacer(minLength: 0)
            parts(status)
        }
    }

    private func name(lines: Int) -> some View {
        Text(verbatim: WorkCardWords.title(card))
            .font(card.kind == .command ? PebbleFont.cardDetail : PebbleFont.cardBody)
            .foregroundStyle(PebbleColor.text)
            .lineLimit(lines)
            .truncationMode(.middle)
    }

    private var mark: some View {
        Image(systemName: ViewSymbol.card(card.kind))
            .foregroundStyle(PebbleColor.secondaryText)
            .accessibilityHidden(true)
    }

    /// What follows the name: the lines a files card changed, its state in words, and in Details when it happened.
    @ViewBuilder private func parts(_ status: (words: String, tone: WorkTone)?) -> some View {
        if card.kind == .files {
            let diff = card.diff
            Text(AppCopy.Views.diff(added: diff.added, removed: diff.removed))
                .font(PebbleFont.chip.monospacedDigit())
                .foregroundStyle(PebbleColor.secondaryText)
                .fixedSize()
                .accessibilityLabel(AppCopy.Views.linesChanged(added: diff.added, removed: diff.removed))
        }
        if let status {
            ToneLabel(status.words, tone: status.tone)
        }
        if showsTime, let time = card.items.first.flatMap({ AppCopy.Details.offset($0.at) }) {
            Text(time)
                .font(PebbleFont.meta.monospacedDigit())
                .foregroundStyle(PebbleColor.mutedText)
                .fixedSize()
        }
    }
}

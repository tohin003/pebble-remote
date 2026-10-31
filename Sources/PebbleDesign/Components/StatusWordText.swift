import PebbleProtocol
import SwiftUI

/// Pebble's status word for a key, rotating synonyms every 3 s inside the key (fixed under Reduce Motion), with an
/// optional exact elapsed time. VoiceOver hears the key's stable sentence and the time, never a rotating synonym.
/// Updates at most once a second.
///
/// With `stacksAtLargeSizes` (the run bar), accessibility text sizes put the word on its own line and the time on the
/// next, so neither is cut off; the word then stays the key's own (no rotation), so the bar doesn't change height every
/// few seconds, and it may wrap rather than truncate.
struct StatusWordText: View {
    let status: StatusKey
    var attempt: Int?
    /// When the word first showed (rotation counts from here). Defaults to the shared rotation clock, so every place
    /// that shows the same run shows the same word at once (U-03).
    var shownSince: Date?
    /// Pebble's run start, for "2 min 05 s".
    var startedAt: Date?
    /// False when `startedAt` was counted by the phone, not Pebble: the time then shows with "~".
    var exact: Bool = true
    var wordFont: Font = PebbleFont.statusWord
    var timeFont: Font = PebbleFont.elapsed
    var wordStyle: AnyShapeStyle = AnyShapeStyle(PebbleColor.text)
    var timeStyle: AnyShapeStyle = AnyShapeStyle(PebbleColor.mutedText)
    var stacksAtLargeSizes = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let origin = shownSince ?? StatusCopy.rotationEpoch
        let stacked = stacksAtLargeSizes && typeSize.isAccessibilitySize
        TimelineView(.periodic(from: origin, by: 1)) { context in
            let word = StatusCopy.word(
                for: status, shownFor: context.date.timeIntervalSince(origin), rotate: !reduceMotion && !stacked,
                attempt: attempt)
            let elapsed = startedAt.flatMap { start -> String? in
                let seconds = context.date.timeIntervalSince(start)
                return exact ? StatusCopy.formatExactElapsed(seconds) : StatusCopy.formatElapsed(seconds).map(StatusCopy.approximate)
            }
            let layout =
                stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PebbleSpace.s2))
            layout {
                Text(word)
                    .font(wordFont)
                    .foregroundStyle(wordStyle)
                    .lineLimit(stacked ? 2 : 1)
                    .contentTransition(.opacity)
                if let elapsed {
                    Text(elapsed)
                        .font(timeFont)
                        .foregroundStyle(timeStyle)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StatusCopy.label(for: status))
            .accessibilityValue(
                elapsed.map { AppCopy.Conversation.elapsedAccessibility($0.replacingOccurrences(of: "~", with: ""), exact: exact) }
                    ?? "")
        }
    }
}

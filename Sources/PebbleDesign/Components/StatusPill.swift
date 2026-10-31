import PebbleProtocol
import SwiftUI

/// Pebble's status word in a capsule: in chat rows ("Editing"), live run rows, the conversation header.
/// The symbol and the word say what Pebble is doing; colour follows the tone (busy, needs you, waiting, problem) but
/// never carries it alone. The word rotates inside its key every 3 s (fixed under Reduce Motion); VoiceOver hears the
/// key's one stable sentence. Content layer: a soft fill, never glass.
///
/// ```swift
/// StatusPill(status: chat.status)
/// StatusPill(status: run.status, since: run.started)   // "Editing · 2 min 05 s"
/// ```
public struct StatusPill: View {
    let status: StatusKey
    let since: Date?
    let attempt: Int?
    let exact: Bool

    /// - Parameters:
    ///   - since: Pebble's run start; shows the exact elapsed time after the word.
    ///   - attempt: the reconnect attempt, shown only for `.reconnecting` ("Reconnecting (try 2)").
    ///   - exact: false when `since` was counted by this phone (the time then shows with "~").
    public init(status: StatusKey, since: Date? = nil, attempt: Int? = nil, exact: Bool = true) {
        self.status = status
        self.since = since
        self.attempt = attempt
        self.exact = exact
    }

    public var body: some View {
        let tone = StatusCopy.tone(of: status)
        HStack(spacing: PebbleSpace.s1) {
            Image(systemName: PebbleSymbol.status(status))
                .imageScale(.small)
                .accessibilityHidden(true)
            StatusWordText(
                status: status, attempt: attempt, startedAt: since, exact: exact, wordFont: PebbleFont.chip,
                timeFont: PebbleFont.chip.monospacedDigit(), wordStyle: AnyShapeStyle(ink(tone)),
                timeStyle: AnyShapeStyle(PebbleColor.secondaryText))
        }
        .font(PebbleFont.chip)
        .foregroundStyle(ink(tone))
        .padding(.horizontal, PebbleSpace.s2 + 2)
        .padding(.vertical, PebbleSpace.s1)
        .fixedSize()  // a chip never truncates Pebble's word; the row around it decides the layout
        .background(fill(tone), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private func ink(_ tone: StatusTone) -> Color {
        switch tone {
        case .working, .needsYou: PebbleColor.accent
        case .waiting: PebbleColor.secondaryText
        case .problem: PebbleColor.danger
        }
    }

    private func fill(_ tone: StatusTone) -> Color {
        switch tone {
        case .working, .needsYou: PebbleColor.soft
        case .waiting, .problem: PebbleColor.hover
        }
    }
}

#if os(iOS)
#Preview("Status pills") {
    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
        StatusPill(status: .editing, since: .now.addingTimeInterval(-125))
        StatusPill(status: .thinking)
        StatusPill(status: .review)
        StatusPill(status: .reconnecting, attempt: 2)
        StatusPill(status: .error)
        StatusPill(status: .paused)
    }
    .padding()
}
#endif

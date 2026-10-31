import PebbleProtocol
import SwiftUI

/// The live run, in one line: the pebble, Pebble's status word, the exact elapsed time from Pebble's own run start,
/// what it works on, and Pause/Resume and Stop. "Editing · Fix login · 2 min 05 s".
///
/// It belongs to the control layer:
/// - above the composer in a conversation, as one Liquid Glass capsule (`chrome: .glass`, the default);
/// - in the tab bar's bottom accessory, where the system already draws the glass (`chrome: .plain`).
/// Its buttons are plain inside that glass (never glass on glass) and keep 44 pt hit regions. Stop never says it
/// undoes anything: steps that already ran stay.
///
/// With `onOpen`, the pebble and the words are one button that opens the run's conversation (the bottom accessory),
/// so VoiceOver finds it as a button rather than a tap-only area. Pass `animated: false` when another animated pebble
/// is already in view: one animated avatar per window. Pass `onStop: nil` when another bar on the screen already has
/// the run's Stop: one Stop per screen.
public struct RunBar: View {
    public enum Chrome: Sendable { case glass, plain }

    let status: StatusKey
    let title: String
    let startedAt: Date?
    let isPaused: Bool
    let attempt: Int?
    let exact: Bool
    let stealth: Bool
    let animated: Bool
    let chrome: Chrome
    let onStop: (() -> Void)?
    let onPauseToggle: (() -> Void)?
    let onOpen: (() -> Void)?

    /// - Parameters:
    ///   - status: Pebble's status key for the run (never built from a progress label).
    ///   - title: the conversation's title, or what the run works on; may be empty.
    ///   - startedAt: Pebble's run start (exact), or the phone's estimate with `exact: false` ("~2 min").
    ///   - animated: whether the pebble moves; false when another animated pebble is in view.
    ///   - onStop: nil hides Stop (another bar on the screen has it).
    ///   - onPauseToggle: nil hides Pause/Resume (when Pebble doesn't offer it).
    ///   - onOpen: opens the run's conversation from the pebble and the words; nil leaves them plain.
    public init(
        status: StatusKey, title: String, startedAt: Date?, isPaused: Bool, attempt: Int? = nil, exact: Bool = true,
        stealth: Bool = false, animated: Bool = true, chrome: Chrome = .glass, onStop: (() -> Void)?,
        onPauseToggle: (() -> Void)? = nil, onOpen: (() -> Void)? = nil
    ) {
        self.status = status
        self.title = title
        self.startedAt = startedAt
        self.isPaused = isPaused
        self.attempt = attempt
        self.exact = exact
        self.stealth = stealth
        self.animated = animated
        self.chrome = chrome
        self.onStop = onStop
        self.onPauseToggle = onPauseToggle
        self.onOpen = onOpen
    }

    private var shownStatus: StatusKey { isPaused ? .paused : status }

    public var body: some View {
        let summary = RunBarSummary(
            status: shownStatus, title: title, startedAt: isPaused ? nil : startedAt, attempt: attempt, exact: exact,
            stealth: stealth, animated: animated)
        let content = HStack(spacing: PebbleSpace.s3) {
            if let onOpen {
                Button(action: onOpen) {
                    summary
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppCopy.Conversation.open)
            } else {
                summary
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let onPauseToggle {
                Button(
                    isPaused ? AppCopy.Conversation.resume : AppCopy.Conversation.pause,
                    systemImage: isPaused ? PebbleSymbol.resume : PebbleSymbol.pause, action: onPauseToggle
                )
                .labelStyle(.iconOnly)
                .buttonStyle(RunBarButtonStyle())
            }
            if let onStop {
                Button(AppCopy.Conversation.stop, systemImage: PebbleSymbol.stop, action: onStop)
                    .labelStyle(.iconOnly)
                    .buttonStyle(RunBarButtonStyle())
                    .accessibilityHint(AppCopy.Conversation.stopHint)
            }
        }
        .padding(.leading, PebbleSpace.s3)
        .padding(.trailing, PebbleSpace.s1)
        .padding(.vertical, PebbleSpace.s1)

        switch chrome {
        case .glass:
            content.glassEffect(.regular, in: .capsule)
        case .plain:
            content
        }
    }
}

/// The pebble, Pebble's status word with the time, and what the run works on: the part of the bar that opens the
/// conversation when the bar has `onOpen`.
private struct RunBarSummary: View {
    let status: StatusKey
    let title: String
    let startedAt: Date?
    let attempt: Int?
    let exact: Bool
    let stealth: Bool
    let animated: Bool

    var body: some View {
        HStack(spacing: PebbleSpace.s3) {
            PebbleAvatar(status: status, stealth: stealth, animated: animated)
                .frame(width: PebbleSize.avatarInline, height: PebbleSize.avatarInline)
            VStack(alignment: .leading, spacing: 2) {
                // On glass: the word in the system's vibrant primary, the time and title in Pebble's secondary text
                // colour, which keeps 4.5:1 where the dimmed `.secondary` failed the accessibility audit. At
                // accessibility text sizes the word takes its own line and the time the next (StatusWordText).
                StatusWordText(
                    status: status, attempt: attempt, startedAt: startedAt, exact: exact,
                    wordStyle: AnyShapeStyle(.primary), timeStyle: AnyShapeStyle(PebbleColor.secondaryText),
                    stacksAtLargeSizes: true)
                if !title.isEmpty {
                    Text(verbatim: title)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A plain icon button with at least a 44 pt hit region, for use inside glass. The symbol follows the text size, and the
/// region grows with it.
private struct RunBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(minWidth: PebbleSize.minTap, minHeight: PebbleSize.minTap)
            .contentShape(.circle)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

#if os(iOS)
#Preview("Run bar") {
    @Previewable @State var paused = false
    VStack {
        Spacer()
        RunBar(
            status: .editing, title: "Fix login", startedAt: .now.addingTimeInterval(-125), isPaused: paused,
            onStop: {}, onPauseToggle: { paused.toggle() })
        RunBar(status: .thinking, title: "", startedAt: .now, isPaused: false, chrome: .plain, onStop: {})
    }
    .padding()
}
#endif

import CoreGraphics
import PebbleRemoteKit
import SwiftUI

/// Where the transcript stays as it changes: calm scrolling (the UX audit's U-11, U-15, U-25, U-30), with Pebble's
/// own rule (scrollStick.ts): new content is followed only while the person is at the end, a person reading above
/// keeps their place, and sending always shows the end.
enum TranscriptScroll {
    /// Pebble's `STICK_PX`: within 48 points of the end counts as at the end.
    static let stickDistance: CGFloat = 48

    /// What the transcript holds on to while its content or its bars change.
    enum Stick: Equatable {
        /// The end: what Pebble writes stays in view, right above the composer.
        case end
        /// A waiting card's top, as the conversation opened on it, until the person scrolls.
        case card(String)
        /// Where the person scrolled to: nothing moves it.
        case free
    }

    /// The card a conversation opens on: the first of the cards that wait for the person at its end (a review, a
    /// question, the task's decisions, a command, the handoff offer), so its heading is in view rather than under the
    /// navigation bar. Nil opens at the end, as Pebble's window does.
    static func openingCard(in items: [TranscriptItem]) -> String? {
        var first: String?
        for item in items.reversed() {
            guard waitsForPerson(item) else { break }
            first = item.id
        }
        return first
    }

    /// A card that waits for the person's decision or check.
    static func waitsForPerson(_ item: TranscriptItem) -> Bool {
        switch item {
        case .review, .question, .task, .handoff, .command: true
        case .message, .activity, .runEnd, .action: false
        }
    }

    /// Where the person is, from two frames on screen: the transcript's stack, and the space between the bars (the
    /// navigation bar above; the run bar, chips, composer, keyboard and tab bar below). Frames rather than the scroll
    /// view's own geometry: on the iPhone its container size is already the space between the bars, so subtracting the
    /// bars again put "the end" a bar's height too high, and "Jump to Latest" showed at the end of every conversation
    /// (the re-check's U-15 and U-49: in the held change the stack ended at y 641, exactly where the space did).
    struct Metrics: Equatable {
        /// The transcript's stack, with its vertical padding, on screen.
        var stack: CGRect = .zero
        /// The space between the bars, on screen.
        var visible: CGRect = .zero
        /// The top of the first card at the end that waits for the person, on screen; nil when there is none.
        var waitingCardTop: CGFloat?

        /// Both frames are known.
        var isMeasured: Bool { stack.height > 0 && visible.height > 0 }

        /// The transcript is taller than the space between the bars.
        var canScroll: Bool { stack.height > visible.height + 1 }

        /// How far the transcript's end lies below the end of the space (negative: above it, with empty space under it).
        var distanceToEnd: CGFloat { stack.maxY - visible.maxY }

        /// The person is at the end, within Pebble's 48 points.
        var isAtEnd: Bool { !canScroll || distanceToEnd <= TranscriptScroll.stickDistance }

        /// The end sits right above the bars: not hidden under them, and no empty space under it.
        var restsAtEnd: Bool { abs(distanceToEnd) <= 2 }

        /// An empty band lies between the transcript's end and the bars: scrolled past the end (the re-check's 024,
        /// 048 and 110, after opening on a card that fits).
        var hasBandUnderEnd: Bool { distanceToEnd < -2 }

        /// A card that waits for the person shows in the space (its top is above the space's end).
        var waitingCardInView: Bool { waitingCardTop.map { $0 < visible.maxY } ?? false }

        /// "Jump to Latest": only when the person is away from the end of a transcript taller than the space, and no
        /// waiting card is in view (it would sit on the card's own buttons; the card is the newest thing anyway).
        var showsJump: Bool { isMeasured && canScroll && !isAtEnd && !waitingCardInView }

        /// The content or the space changed size (not just where the transcript is scrolled to).
        func layoutChanged(from old: Metrics) -> Bool {
            stack.height != old.stack.height || visible != old.visible
        }
    }
}

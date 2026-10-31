import Accessibility
import PebbleProtocol
import SwiftUI

/// Pebble's rules for speaking status changes (statusWords.ts `announcer`): a changed sentence is spoken at most once
/// per 10 s, and when the window ends only the latest one is spoken (never a stale one); a change and its reversal
/// inside the window say nothing; "Reply finished" is spoken at once and nothing takes it back. Pure state, so it is
/// tested without VoiceOver.
nonisolated struct StatusAnnouncer: Equatable {
    var window: TimeInterval = PebbleMotion.announceInterval
    private(set) var current = ""
    private(set) var pending: String?
    private(set) var lastSpoken = Date.distantPast

    /// When a deferred sentence is due, if one waits.
    var due: Date? { pending == nil ? nil : lastSpoken.addingTimeInterval(window) }

    /// Offers a sentence. Returns what to speak now, if anything; otherwise it waits for `due`.
    mutating func say(_ text: String, at now: Date) -> String? {
        guard !text.isEmpty else { return nil }
        if text == current {
            pending = nil  // a change and its reversal inside the window say nothing
            return nil
        }
        if pending == nil, now.timeIntervalSince(lastSpoken) >= window {
            return deliver(text, at: now)
        }
        pending = text
        return nil
    }

    /// The deferred sentence, if its time has come.
    mutating func fire(at now: Date) -> String? {
        guard let pending, let due, now >= due else { return nil }
        self.pending = nil
        return deliver(pending, at: now)
    }

    /// Speaks at once, outside the window ("Reply finished"); a sentence still waiting is dropped as stale.
    mutating func now(_ text: String, at now: Date) -> String? {
        pending = nil
        guard !text.isEmpty, text != current else { return nil }
        return deliver(text, at: now)
    }

    /// Empties the region without speaking; the next sentence is a change again.
    mutating func clear() {
        pending = nil
        current = ""
    }

    private mutating func deliver(_ text: String, at now: Date) -> String? {
        current = text
        lastSpoken = now
        return text
    }
}

extension View {
    /// Speaks Pebble's status sentences to VoiceOver as Pebble's windows do: the key's stable sentence on a change, at
    /// most once per 10 s, and "Reply finished" once when `finished` turns true. Put it on the one view that shows the
    /// live status (the conversation, or the Pebble tab), not on every row.
    public func pebbleStatusAnnouncements(status: StatusKey?, finished: Bool) -> some View {
        modifier(StatusAnnouncementsModifier(status: status, finished: finished))
    }
}

private struct StatusAnnouncementsModifier: ViewModifier {
    let status: StatusKey?
    let finished: Bool
    @State private var announcer = StatusAnnouncer()
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    func body(content: Content) -> some View {
        content
            .onChange(of: status) { _, new in
                guard voiceOver else { return }
                if let new {
                    if announcer.current == StatusCopy.finishedLabel { announcer.clear() }
                    speak(announcer.say(StatusCopy.label(for: new), at: .now))
                } else if announcer.current != StatusCopy.finishedLabel {
                    announcer.clear()
                }
            }
            .onChange(of: finished) { _, new in
                guard voiceOver, new else { return }
                speak(announcer.now(StatusCopy.finishedLabel, at: .now))
            }
            .task(id: announcer.due) {
                guard let due = announcer.due else { return }
                try? await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                speak(announcer.fire(at: .now))
            }
    }

    private func speak(_ text: String?) {
        guard let text else { return }
        AccessibilityNotification.Announcement(text).post()
    }
}

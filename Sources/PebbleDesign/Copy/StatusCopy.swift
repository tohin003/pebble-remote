import Foundation
import PebbleProtocol

/// Pebble's status words, word for word from `src/statusWords.ts` (`STATUS_WORDS`, `STATUS_LABELS`,
/// `FINISHED_LABEL`, `statusWord`, `statusLabel`, `formatElapsed`, `formatExactElapsed`).
///
/// Every word names what Pebble says it is doing. Synonyms rotate only inside one key, every 3 s, so the meaning never
/// drifts while the words vary. A screen reader hears the key's one stable sentence (`label(for:)`), never a rotating
/// synonym. A progress label (which can hold paths) never becomes a status word: build words only from a `StatusKey`.
nonisolated public enum StatusCopy {
    /// `STATUS_WORDS`: the visible words for each key, first word first.
    public static let words: [StatusKey: [String]] = [
        .thinking: [
            "Thinking", "Reasoning it through", "Weighing options", "Working it out", "Joining the dots", "Turning it over",
        ],
        .writing: ["Writing", "Drafting a reply", "Putting it into words"],
        .reading: ["Reading", "Reading closely"],
        .searching: ["Searching", "Looking it up", "Scanning for matches"],
        .editing: ["Editing", "Drafting changes", "Shaping the change"],
        .testing: ["Testing", "Checking", "Running checks", "Running tests"],
        .running: ["Running a command", "Handling a command"],
        .delegating: ["Coordinating agents", "Checking on agents"],
        .viewing: ["Building a view", "Laying out a view"],
        .working: ["Working", "On it"],
        .loading: ["Loading model", "Warming up the model"],
        .question: ["Waiting for you", "Needs your answer"],
        .review: ["Needs your review", "Waiting for your review"],
        .reconnecting: ["Reconnecting"],
        .blocked: ["Blocked"],
        .uncertain: ["Needs a check"],
        .offline: ["Offline"],
        .paused: ["Paused"],
        .error: ["Hit a problem"],
        .sending: ["Sending"],
    ]

    /// `STATUS_LABELS`: one stable sentence per key, for VoiceOver and announcements.
    public static let labels: [StatusKey: String] = [
        .thinking: "Pebble is thinking",
        .writing: "Pebble is writing a reply",
        .reading: "Pebble is reading",
        .searching: "Pebble is searching",
        .editing: "Pebble is editing",
        .testing: "Pebble is testing",
        .running: "Pebble is running a command",
        .delegating: "Pebble is coordinating agents",
        .viewing: "Pebble is building a view",
        .working: "Pebble is working",
        .loading: "Pebble is loading the model",
        .question: "Pebble is waiting for your answer",
        .review: "An action needs your review",
        .reconnecting: "Pebble is reconnecting to the model",
        .blocked: "The task is blocked",
        .uncertain: "An outcome needs a check",
        .offline: "The local service is offline",
        .paused: "The task is paused",
        .error: "The task hit a problem",
        .sending: "Sending your message",
    ]

    /// `FINISHED_LABEL`: said once, at once, when a reply completes.
    public static let finishedLabel = "Reply finished"

    /// The two keys that wait for the person keep one name and never rotate (UX audit U-13): rotating synonyms suit
    /// work in progress, but "Waiting for you" then "Needs your answer" reads as two states. These are Pebble's own
    /// fixed phrases for them (goals.py's inbox rows "Needs your answer" and "Needs your review", App.vue's "Needs your
    /// review" group), both already in `words`.
    public static let fixedWords: [StatusKey: String] = [
        .question: "Needs your answer",
        .review: "Needs your review",
    ]

    /// Whether a key's word changes over time: only work in progress, with more than one word, rotates.
    public static func rotates(_ key: StatusKey) -> Bool {
        fixedWords[key] == nil && (words[key]?.count ?? 0) > 1
    }

    /// The one clock every rotating word counts from (UX audit U-03): with it, each copy of a run's word on a screen (the
    /// hero, a list's pill, the run bar) shows the same synonym at the same moment, instead of each counting from when
    /// it appeared.
    public static let rotationEpoch = Date(timeIntervalSinceReferenceDate: 0)

    /// The word at `date` on the shared clock (`rotationEpoch`).
    public static func word(for key: StatusKey?, at date: Date, rotate: Bool = true, attempt: Int? = nil) -> String {
        word(for: key, shownFor: date.timeIntervalSince(rotationEpoch), rotate: rotate, attempt: attempt)
    }

    /// The word for an unknown key (`statusWord`'s fallback).
    public static let fallbackWord = "Working"
    /// The sentence for an unknown key (`statusLabel`'s fallback).
    public static let fallbackLabel = "Pebble is working"

    /// `statusWord(key, tick, rotate, attempt)`: the word at rotation step `tick`. Only `reconnecting` shows a count,
    /// for an attempt from 1 to 99: "Reconnecting (try 2)".
    public static func word(for key: StatusKey?, tick: Int = 0, rotate: Bool = true, attempt: Int? = nil) -> String {
        guard let key, let list = words[key], !list.isEmpty else { return fallbackWord }
        if let fixed = fixedWords[key] { return fixed }
        let step = rotate ? tick.magnitude % UInt(list.count) : 0
        let word = list[Int(step)]
        if key == .reconnecting, let attempt, (1...99).contains(attempt) {
            return "\(word) (try \(attempt))"
        }
        return word
    }

    /// The word after the key has been shown for `seconds` (one step per `PebbleMotion.rotateInterval`).
    public static func word(for key: StatusKey?, shownFor seconds: TimeInterval, rotate: Bool = true, attempt: Int? = nil)
        -> String
    {
        let tick = seconds.isFinite && seconds > 0 ? Int(min(seconds / PebbleMotion.rotateInterval, 9e15)) : 0
        return word(for: key, tick: tick, rotate: rotate, attempt: attempt)
    }

    /// `statusLabel(key)`: the stable accessible sentence.
    public static func label(for key: StatusKey?) -> String {
        guard let key, let label = labels[key] else { return fallbackLabel }
        return label
    }

    /// `formatElapsed(ms)`: approximate elapsed time counted by this phone ("12s", "3 min", "1 h 05 min"); nil under
    /// a second. Show it with "~" (`approximate(_:)`), because Pebble did not count it.
    public static func formatElapsed(milliseconds ms: Double) -> String? {
        guard ms.isFinite, ms >= 1000 else { return nil }
        let s = Int(min(ms / 1000, 9e15).rounded(.down))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h \(twoDigits(m % 60)) min"
    }

    /// `formatExactElapsed(ms)`: exact elapsed time from Pebble's own run start ("12 s", "1 min 05 s", "1 h 02 min");
    /// nil under a second. Shown without "~", because Pebble counted it.
    public static func formatExactElapsed(milliseconds ms: Double) -> String? {
        guard ms.isFinite, ms >= 1000 else { return nil }
        let s = Int(min(ms / 1000, 9e15).rounded(.down))
        if s < 60 { return "\(s) s" }
        let m = s / 60
        if m < 60 { return "\(m) min \(twoDigits(s % 60)) s" }
        return "\(m / 60) h \(twoDigits(m % 60)) min"
    }

    /// `formatElapsed` for a time interval in seconds.
    public static func formatElapsed(_ seconds: TimeInterval) -> String? {
        formatElapsed(milliseconds: seconds * 1000)
    }

    /// `formatExactElapsed` for a time interval in seconds.
    public static func formatExactElapsed(_ seconds: TimeInterval) -> String? {
        formatExactElapsed(milliseconds: seconds * 1000)
    }

    /// An approximate time as Pebble shows it: "~12s".
    public static func approximate(_ text: String) -> String { "~" + text }

    /// `exactChangeIn(ms)`: milliseconds until `formatExactElapsed` changes.
    public static func exactChangeIn(milliseconds ms: Double) -> Double {
        guard ms.isFinite, ms >= 0 else { return 1000 }
        if ms < 3_600_000 { return 1000 - ms.truncatingRemainder(dividingBy: 1000) }
        return 60000 - ms.truncatingRemainder(dividingBy: 60000)
    }

    /// `elapsedChangeIn(ms)`: milliseconds until `formatElapsed` changes.
    public static func elapsedChangeIn(milliseconds ms: Double) -> Double {
        guard ms.isFinite, ms >= 0 else { return 1000 }
        if ms < 60000 { return 1000 - ms.truncatingRemainder(dividingBy: 1000) }
        return 60000 - ms.truncatingRemainder(dividingBy: 60000)
    }

    /// The meaning group of a key, which decides its colour and avatar pose.
    public static func tone(of key: StatusKey) -> StatusTone {
        switch key {
        case .question, .review: .needsYou
        case .blocked, .uncertain, .offline, .error: .problem
        case .paused, .reconnecting: .waiting
        default: .working
        }
    }

    static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// How a status reads at a glance. Colour follows the tone; the word and symbol always say it too.
nonisolated public enum StatusTone: Sendable, Hashable {
    /// Pebble is busy (thinking, editing, sending...).
    case working
    /// Pebble waits for the person (a question, a review).
    case needsYou
    /// Pebble is held up but not stuck on the person (paused, reconnecting).
    case waiting
    /// Something went wrong or needs a check.
    case problem
}

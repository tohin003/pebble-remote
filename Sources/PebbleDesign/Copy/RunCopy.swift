import Foundation
import PebbleProtocol

/// How a run's end reads under the reply, ported from Pebble's `src/activity.ts` (`formatDuration`, the one-line
/// summary above a reply): "Thought for 11 s", "Worked for 42 s · 6 steps · waited 1 min for you · 1 retry",
/// "Stopped after 12 s", "Hit a problem after 30 s". A run under a second with no step, retry or wait gets no line:
/// a "hi" gets no chrome. Durations come from Pebble's clock and are never invented.
nonisolated public enum RunCopy {
    /// `formatDuration(seconds)`: "<1 s", "12 s", "1 min 05 s", "2 min", "2 h 03 min"; nil when unknown.
    public static func formatDuration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        if seconds < 1 { return "<1 s" }
        let s = Int(min(seconds, 9e15).rounded())  // JS Math.round: halves round up, as here for positive values
        if s < 60 { return "\(s) s" }
        let m = s / 60, rest = s % 60
        if m < 60 { return rest > 0 ? "\(m) min \(StatusCopy.twoDigits(rest)) s" : "\(m) min" }
        return "\(m / 60) h \(StatusCopy.twoDigits(m % 60)) min"
    }

    /// The lead for a run that ended early or needs something (activity.ts `ENDINGS`).
    static func ending(_ state: RunState) -> String? {
        switch state.rawValue {
        case "stopped": "Stopped after"
        case "failed": "Hit a problem after"
        case "interrupted": "Interrupted after"
        case "paused": "Paused after"
        case "budget_exhausted": "Reached its limit after"
        case "needs_reconciliation": "Needs a check after"
        default: nil
        }
    }

    /// The one line under a settled reply, or nil when there is nothing worth saying.
    /// - Parameters:
    ///   - seconds: how long the run took, from Pebble.
    ///   - steps, retries, waitedSeconds: Pebble's counts for the run.
    ///   - countsKnown: false when Pebble could not count the run (then neither "Worked" nor "Thought" is known).
    public static func endLine(
        state: RunState, seconds: Double?, steps: Int = 0, retries: Int = 0, waitedSeconds: Double = 0,
        countsKnown: Bool = true
    ) -> String? {
        let ending = ending(state)
        let quiet = steps == 0 && retries == 0 && waitedSeconds == 0 && ending == nil
        if quiet && (seconds == nil || seconds! < 1) { return nil }
        let duration = formatDuration(seconds)
        let lead = ending ?? (!countsKnown ? "Took" : steps > 0 ? "Worked for" : "Thought for")
        let head: String
        if let duration {
            head = "\(lead) \(duration)"
        } else if steps > 0 {
            head = "Worked"
        } else if ending != nil {
            head = lead.replacingOccurrences(of: #" (after|for)$"#, with: "", options: .regularExpression)
        } else {
            head = "Thought"
        }
        var parts = [head]
        if steps > 0 { parts.append("\(steps) \(steps == 1 ? "step" : "steps")") }
        if waitedSeconds >= 1, let waited = formatDuration(waitedSeconds) { parts.append("waited \(waited) for you") }
        if retries > 0 { parts.append("\(retries) \(retries == 1 ? "retry" : "retries")") }
        return parts.joined(separator: " · ")
    }

    /// The disclosure's name when there is no line (`summaryTitle`).
    public static let whatPebbleDid = "What Pebble did"
}

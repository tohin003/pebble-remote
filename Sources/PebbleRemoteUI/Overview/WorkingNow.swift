import PebbleDesign
import PebbleRemoteKit

/// Which live runs the Pebble tab lists under Working Now (UX audit U-06): the runs Pebble is working on, and paused
/// ones (Resume is theirs). A run that waits for the person's answer or review is not "working now": it shows where
/// waiting things go, under "Needs your review", with its decision. Until the phone has read that decision, the run stays
/// in Working Now, so it never drops off the tab.
enum WorkingNow {
    static func runs(_ live: [LiveRun], waiting: [WaitingItem]) -> [LiveRun] {
        let decided = Set(waiting.map(\.chatID))
        return live.filter { !waitsForPerson($0) || !decided.contains($0.chatID) }
    }

    /// The run waits for the person's answer or review (Pebble's `question` and `review` keys).
    static func waitsForPerson(_ run: LiveRun) -> Bool {
        StatusCopy.tone(of: run.status) == .needsYou
    }
}

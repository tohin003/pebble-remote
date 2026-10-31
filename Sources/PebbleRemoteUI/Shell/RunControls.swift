import PebbleProtocol
import PebbleRemoteKit

/// Which run controls the phone offers for a run, as Pebble's Mac does (lane V's rule for the UX audit's U-10).
///
/// - **Stop:** Pebble's window offers it only while the conversation's task is active (`state.active`): the composer's
///   Stop, the status line, the companion, ⌘. and `/stop`. Pebble releases its worker while a run waits for an approval
///   or an answer, so a waiting run shows no Stop there: its card or question is the decision (Don't Allow, Cancel
///   Request).
/// - **Pause in a run bar:** nothing runs while Pebble waits for the person, so a waiting run's bar shows its status
///   only. Pebble's Details › Activity still offers Pause for it; the conversation's ⋯ menu, which stands in for it,
///   keeps Pause.
///
/// Working runs (queued, running, reconnecting) keep Stop, and Pause where the bridge offers it. Paused runs keep
/// Resume and Stop.
enum RunControls {
    /// The run waits for the person's decision: an approval (a card) or an answer (a question).
    static func awaitsDecision(_ state: RunState) -> Bool {
        state == .waitingApproval || state == .waitingInput
    }

    /// Whether the run's bar, the bottom accessory and the Pebble tab's rows offer Stop.
    static func offersStop(_ state: RunState) -> Bool {
        !awaitsDecision(state)
    }

    /// Whether the run's bar offers Pause or Resume (the bridge must offer `run_pause` too).
    static func offersPauseInBar(_ state: RunState) -> Bool {
        !awaitsDecision(state)
    }

    /// The run the bottom accessory shows: one Pebble is working on now (queued, running or reconnecting: an active
    /// task), the open conversation's first (iOS 26.0 only: later the accessory hides there). Never a run that waits for
    /// the person or is paused: Reviews and the Chats rows show those (the lead's decision after the re-check's U-04).
    static func accessoryRun(_ runs: [LiveRun], openChat: ChatID?) -> LiveRun? {
        let working = runs.filter { $0.state.isLive }
        return working.first { $0.chatID == openChat } ?? working.first
    }
}

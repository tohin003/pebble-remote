import PebbleProtocol
import PebbleRemoteKit

/// Which of Pebble's task controls show, and how (RunPanel.vue, view "conversation"), given what the bridge offers.
/// Pebble's conditions: Resume for a paused, stopped, interrupted, failed or limit-reached task (with new limits after
/// "Reached this task's limit."); a held task's three decisions, "Run the tests" only in a project; a paused window's
/// Done and End access only with an uncertain step; Details always. A control whose method the bridge doesn't offer
/// stays hidden.
struct TaskControls: Equatable {
    enum Details: Equatable {
        /// The uncertain outcomes (Pebble's Details › Activity holds them).
        case outcomes
        /// What Pebble did in the task.
        case run
    }

    var resume = false
    /// Resume asks for "Step limit" and "Active seconds" first.
    var resumeAsksLimits = false
    var runTests = false
    var askToFinish = false
    var accept = false
    var windowDone = false
    var endAccess = false
    var details: Details?

    /// - Parameters:
    ///   - inConversation: under the conversation, where the run bar already offers Resume for a paused task. On the
    ///     Reviews tab Resume never shows: only held and uncertain tasks are listed there.
    ///   - showsRunDetails: the screen can show what Pebble did (the conversation can; the Reviews tab can't).
    init(task: TaskAttention, offers: (String) -> Bool, inConversation: Bool, showsRunDetails: Bool) {
        resume = task.canResume && task.state != .paused && inConversation && offers("run_resume")
        resumeAsksLimits = resume && task.needsLimits
        if task.isHeld {
            runTests = task.hasProject && offers("run_held_tests")
            askToFinish = offers("run_held_finish")
            accept = offers("run_held_accept")
        }
        if task.needsCheck {
            windowDone = !task.pausedWindows.isEmpty && offers("screen_handoff_done")
            endAccess = !task.pausedWindows.isEmpty && offers("screen_session_revoke")
            if offers("run_readback") { details = .outcomes }
        } else if showsRunDetails {
            details = .run
        }
    }

    /// The conversation's menu: Resume while no run bar shows (a stopped, interrupted, failed or limit-reached task).
    static func menuResumes(_ task: TaskAttention?, hasRunBar: Bool, offers: (String) -> Bool) -> Bool {
        guard let task, !hasRunBar else { return false }
        return task.canResume && task.state != .paused && offers("run_resume")
    }

    var holdsDecisions: Bool { runTests || askToFinish || accept }
}

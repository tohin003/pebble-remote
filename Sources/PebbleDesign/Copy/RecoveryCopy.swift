import Foundation
import PebbleProtocol

/// Pebble's words for finishing and recovering a task, word for word from its window (read-only Pebble checkout 1.9.28):
/// `src/components/RunPanel.vue` (the task's sentence, Resume and its limits, a held task's three decisions, paused
/// windows), `ReconcilePanel.vue` (uncertain outcomes), `ExecutionOutput.vue` (a command), `ModelHandoff.vue` and
/// `src/App.vue` (continuing on the new model, the undo buttons and their notices, "Always allow"). Pebble's sentences
/// are kept exactly; its button labels take Apple's title style, as the rest of the app's buttons do ("Don't Allow").
/// `PebbleParityTests` compares them with Pebble's files.
nonisolated public enum RecoveryCopy {
    // MARK: - The task's state (RunPanel `SENTENCES`)

    nonisolated public enum Task {
        /// Each state as a sentence, never the internal name.
        public static func sentence(_ state: RunState) -> String {
            switch state.rawValue {
            case "queued": "Pebble is about to start."
            case "running": "Pebble is working on this."
            case "retry_wait": "Pebble is reconnecting."
            case "waiting_approval": "Waiting for your approval."
            case "waiting_input": "Waiting for your answer."
            case "paused": "Paused."
            case "stopped": "Stopped."
            case "failed": "Stopped by an error."
            case "interrupted": "Interrupted when Pebble closed."
            case "budget_exhausted": "Reached this task's limit."
            case "needs_reconciliation": "One step has an uncertain outcome. Check it before resuming."
            case "verification_required": "Pebble's change isn't verified yet."
            case "completed": "Done."
            default: unknown
            }
        }

        /// A state from a newer Pebble.
        public static let unknown = "This task is in an unknown state."
        /// After Done on a window the uncertain step paused (F254).
        public static let checked = "Checked: Pebble can use the window again. Send a message to continue."

        /// The sentence a task shows, checked or not.
        public static func sentence(_ state: RunState, windowChecked: Bool) -> String {
            state == .needsReconciliation && windowChecked ? checked : sentence(state)
        }

        public static let resume = "Resume"
        /// Resume after "Reached this task's limit." asks for the new limits first.
        public static let resumeWithLimits = "Resume\u{2026}"
        public static let details = "Details"
        /// The task's group, as Pebble's window labels it.
        public static let label = "Task controls"
        public static let resumeHint = "Pebble picks up where it stopped. Steps that already ran aren't run again."
        public static let detailsHint = "Shows what Pebble did in this task"
        public static let outcomesHint = "Shows the uncertain outcomes and what you can do about each"
    }

    // MARK: - Resume after "Reached this task's limit." (RunPanel's two number fields; runtime.RunLimits)

    nonisolated public enum Limits {
        public static let title = "Resume This Task"
        public static let stepLimit = "Step limit"
        public static let activeSeconds = "Active seconds"
        /// The fields' ranges, as Pebble's own refusal says them.
        public static let range = "Choose 1\u{2013}256 steps and 1\u{2013}86400 seconds per run."
        public static let resume = Task.resume
        public static func minutes(_ seconds: Int) -> String {
            seconds < 60 ? "\(seconds) s" : seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s"
        }
    }

    // MARK: - A task held for verification (RunPanel "Finish this task")

    nonisolated public enum Held {
        /// The group's name in Pebble's window.
        public static let title = "Finish this task"
        public static let runTheTests = "Run the Tests"
        public static let askPebbleToFinish = "Ask Pebble to Finish"
        public static let acceptAsUnverified = "Accept as Unverified"
        /// The question before accepting.
        public static let acceptQuestion = "Keep this change without verification? Pebble records that you decided."
        public static let cancel = "Cancel"
        public static let runTheTestsHint = "Pebble proposes the tests as a card for you to review."
        public static let askPebbleToFinishHint = "Pebble tries once more to verify its change."
        public static let acceptHint = "Asks for Face ID, then keeps the change without verification."
    }

    // MARK: - A window the uncertain step paused (RunPanel's paused windows)

    nonisolated public enum PausedWindow {
        /// Pebble names the app by the last part of its bundle id ("calculator"), else "The app".
        public static func app(_ name: String?) -> String {
            guard let name, !name.isEmpty else { return theApp }
            return name
        }
        public static let theApp = "The app"
        public static func label(_ app: String) -> String { "Paused window: \(app)" }
        public static func sentence(_ app: String) -> String {
            "\(app)'s window is paused because the last step's result is uncertain. Look at it: if it looks right, press Done and Pebble can use it again; then send a message to continue."
        }
        public static let done = "Done"
        public static let endAccess = "End Access"
        public static let doneHint = "Pebble can use the window again"
        public static let endAccessHint = "Pebble stops using this window"
    }

    // MARK: - Uncertain outcomes (ReconcilePanel.vue)

    nonisolated public enum Outcomes {
        /// The panel's name in Pebble's window.
        public static let title = "Uncertain Outcomes"
        public static let intro =
            "Pebble lost track of these actions before it could confirm their outcome. Nothing is retried. Settle each one before resuming."
        public static let waitsForTask = "Pebble reads these back once the current task ends."
        public static let none = "No uncertain outcome is waiting."
        public static let reading = "Reading back"

        /// `VERDICTS`: what Pebble's readback shows.
        public static func verdict(_ verdict: String) -> String {
            switch verdict {
            case "occurred": "Pebble\u{2019}s readback shows this happened."
            case "not_occurred": "Pebble\u{2019}s readback shows this did not happen."
            case "diverged": "The current state matches neither the before nor the after state."
            default: "Pebble cannot tell whether this happened."
            }
        }

        /// The outcome's name: its tool, and its kind when Pebble knows it.
        public static func label(tool: String?, kind: String?) -> String {
            (tool.flatMap { $0.isEmpty ? nil : $0 } ?? "Tool call") + (kind.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? "")
        }

        /// "Basis: after present". A few of Pebble's basis codes use an internal word this app doesn't show ("exit
        /// …" for the record of a command's exit); the phone says "record" there instead.
        public static func basis(_ basis: String) -> String {
            let words = (basis.isEmpty ? "unknown" : basis).replacingOccurrences(of: "_", with: " ")
            return "Basis: "
                + words.replacingOccurrences(
                    of: BannedWords.pattern, with: "record", options: [.regularExpression, .caseInsensitive])
        }

        public static let settle = "Settle from Readback"
        public static func settleLabel(_ label: String) -> String { "Settle \(label) from Pebble\u{2019}s readback" }
        public static let reportYourself = "Report it yourself (recorded as unverified)"
        public static let happened = "It happened"
        public static let didNotHappen = "It did not happen"
        public static func whatYouChecked(_ label: String) -> String { "What you checked for \(label)" }
        public static let notePlaceholder = "What you checked"
        public static let record = "Record My Report"
    }

    // MARK: - A command (ExecutionOutput.vue)

    nonisolated public enum Command {
        /// The command's summary: "Command: running".
        public static func summary(_ state: String) -> String { "Command: " + state.replacingOccurrences(of: "_", with: " ") }
        public static let unknownOutcome =
            "The service did not observe this outcome. Inspect external effects before retrying. This run still requires verification."
        public static let observedOutcome = "Observed outcome"
        public static func observation(_ value: String) -> String {
            switch value {
            case "effect_observed": "Effect observed"
            case "no_effect_observed": "No effect observed"
            default: "Still uncertain after inspection"
            }
        }
        public static let inspectionNote = "Inspection note"
        public static let inspectionNoteHint =
            "Recording an inspection allows newly reviewed project actions. Prior effects remain unverified."
        public static let recordInspection = "Record My Inspection"
        public static let inspectionRecorded = "Inspection recorded. Command effects remain unverified."
        public static let passwordPrompt =
            "Password prompt: what you type is sent to the command only. It is not shown, not stored and the model cannot answer it."
        public static let typeInto = "Type into the Command"
        /// The field's name, as Pebble's window labels it.
        public static let typeIntoField = "Type into the command"
        public static let sendLine = "Send Line"
        public static let ctrlC = "Send Ctrl-C"
        public static let ctrlD = "Send Ctrl-D"
        public static let readOutput = "Read Output"
        public static let nextOutputPage = "Next Output Page"
        public static let stop = "Stop Command"
        public static let forgetOutput = "Forget Saved Command Output"
        public static let partialOutput = "Saved output is a partial record of this command."
        public static func controlsHidden(_ count: Int) -> String {
            "Terminal control sequences hidden on this page: \(count). The raw output bytes are kept."
        }
        /// The output's section, as Pebble's window labels it.
        public static let output = "Command output"
        /// The phone's own sentence when a running command reads no typing (Pebble's window shows no field then).
        public static let takesNoTyping = "This command isn't waiting for anything you type."
        public static let stopHint = "Stops this command. What it already did isn't undone."
        public static let noOutputYet = "No output yet."
    }

    // MARK: - Undo (App.vue's buttons and their notices)

    nonisolated public enum Undo {
        public static let edit = "Undo This Edit"
        public static let command = "Undo This Command"
        public static let change = "Undo This Change"
        public static let gitPlan = "Propose Undo (New Reviewed Plan)"
        /// The notices after each.
        public static let editUndone = "Edit undone"
        public static let commandUndone = "Command undone"
        public static let changeUndone = "Change undone"
        public static let someChangesNotUndone = "Some changes could not be undone"
        public static let undoPlanReady = "Undo plan ready for review"
        public static let hint = "Asks for Face ID, then puts the files back as they were before"
        public static let gitPlanHint = "Pebble prepares the undo as a new Git plan for you to review"
    }

    // MARK: - Always allow (App.vue)

    nonisolated public enum AlwaysAllow {
        public static let button = "Always Allow"
        public static let hint = "Asks for Face ID, then allows these hosts and folders from now on, and runs this once"
        public static let hosts = "Hosts"
        public static let folders = "Folders"
    }

    // MARK: - Continue with the new model (ModelHandoff.vue; App.vue's Details › Task)

    nonisolated public enum Handoff {
        /// The section's heading in Pebble's Details › Task.
        public static let section = "Continue with the new model"
        public static let title = "Continue on another model"
        public static let intro =
            "Pebble can continue this conversation as a new run on the model you chose. Nothing is sent until you approve this exact handoff and start it. History from another route class is withheld unless it is released. The current run stays as it is. The new route checks its own settings again, and this handoff grants no permission."
        public static let checking = "Checking what this handoff would send\u{2026}"
        public static let review = "Review what would be sent, then approve it."
        public static let approvedNothingSent = "Approved. Nothing has been sent yet."
        public static func started(on destination: String) -> String { "Started a new run on \(className(destination))." }
        public static let from = "From"
        public static let to = "To"
        public static let destinationFingerprint = "Destination fingerprint"
        public static func fingerprint(_ prefix: String) -> String { prefix + "\u{2026}" }
        public static func upload(_ destination: String) -> String {
            "The messages counted below will be uploaded to \(className(destination))."
        }
        public static func messagesSent(_ total: Int) -> String { "Messages that will be sent: \(total)" }
        public static let role = "Role"
        public static func fromClass(_ value: String) -> String { "From \(className(value))" }
        public static let nothingSent = "No message would be sent."
        public static func withheld(_ count: Int) -> String {
            switch count {
            case 0: "No message is withheld."
            case 1: "Withheld: 1 message from another route class. It is not sent."
            default: "Withheld: \(count) messages from another route class. They are not sent."
            }
        }
        public static let withheldIDs = "Withheld message IDs"
        public static func andMore(_ count: Int) -> String { "And \(count) more." }
        public static func released(_ classes: [String]) -> String {
            "Released for this handoff, so sent although it came from another route class: "
                + classes.map(className).joined(separator: ", ") + "."
        }
        public static let approve = "Approve This Handoff"
        public static let approved = "Approved"
        public static let start = "Start the New Run"
        public static let reviewAgain = "Review Again"
        public static let notNow = "Not Now"
        public static let approveHint = "Asks for Face ID. Nothing is sent until you start the new run."
        public static let startHint = "Opens the new conversation on the new model"

        /// `ROLES`. Pebble sends three roles: the person's, its replies, and its own records (every other message,
        /// app.py `model_handoff_preview`), which the phone names without Pebble's internal word for them.
        public static func role(_ role: String) -> String {
            switch role {
            case "user": "Your messages"
            case "assistant": "Pebble\u{2019}s replies"
            default: ownRecords
            }
        }
        /// The phone's words for Pebble's third role (Pebble's own word for it is one this app doesn't show).
        public static let ownRecords = "Records Pebble kept"

        /// `className`: a route class as Pebble names it. Pebble's "This device" is the Mac; on the phone it says so.
        public static func className(_ value: String) -> String {
            if value == "device" { return thisMac }
            if value == "unknown" { return "An unrecorded route" }
            if value.hasPrefix("cloud:") { return String(value.dropFirst("cloud:".count)) }
            return value
        }
        /// Pebble's words on the Mac ("this device" there is the Mac itself).
        public static let thisDevicePebble = "This device"
        /// The phone's variant: only the place changes.
        public static let thisMac = "Your Mac"
    }
}

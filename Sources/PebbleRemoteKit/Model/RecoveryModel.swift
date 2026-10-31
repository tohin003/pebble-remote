import Foundation
import PebbleProtocol

// What a person away from the Mac needs to finish or recover a task (lane R, the person's R6): a task held for
// verification, a task that stopped short (Resume, with new limits after "Reached this task's limit."), uncertain
// outcomes and the windows they paused, Undo on what Pebble did, "Always allow" on a card, a running command, and
// continuing on the new model. Shapes and conditions are Pebble's own (read-only Pebble checkout 1.9.28:
// src/components/RunPanel.vue, ReconcilePanel.vue, ExecutionOutput.vue, ModelHandoff.vue and src/App.vue;
// backend/pebble/app.py, controller.py, runtime.py, reconcile.py, process_jobs.py, process_reviews.py,
// companion_tools.py).

// MARK: - The conversation's task

/// A conversation's current task when it needs the person (RunPanel.vue `current`: the live run, else one with a pending
/// question, else one waiting for approval, else the newest). Pebble's window says its state in a sentence under the
/// conversation and offers what the state allows: Resume, the three decisions on a held task, the paused windows of an
/// uncertain step. The phone shows the same under the transcript, and the two Pebble waits on (held, uncertain) on the
/// Reviews tab too.
public struct TaskAttention: Sendable, Hashable, Identifiable {
    public var id: String { "\(chatID)/\(runID)" }
    public var chatID: ChatID
    public var chatTitle: String
    public var runID: RunID
    public var state: RunState
    /// Pebble's note on how it ended, only the sentences meant for the person (PersonNote).
    public var note: String?
    /// The conversation has a project folder: "Run the tests" is offered only there (Pebble tests only in a project).
    public var hasProject: Bool
    /// When the run last changed, by Pebble's clock (the Reviews tab's order).
    public var updated: Date?
    /// The person pressed Done on a window this task paused: "Checked: Pebble can use the window again." (F254).
    public var windowChecked: Bool
    /// The windows this conversation's uncertain step paused (screen sessions Pebble reports as "interrupted"), once the
    /// phone has read them.
    public var pausedWindows: [ScreenSession]

    public init(
        chatID: ChatID, chatTitle: String, runID: RunID, state: RunState, note: String? = nil, hasProject: Bool = false,
        updated: Date? = nil, windowChecked: Bool = false, pausedWindows: [ScreenSession] = []
    ) {
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.runID = runID
        self.state = state
        self.note = note
        self.hasProject = hasProject
        self.updated = updated
        self.windowChecked = windowChecked
        self.pausedWindows = pausedWindows
    }

    /// RunPanel `canResume`: Resume shows for these.
    public var canResume: Bool { Self.resumable.contains(state) }
    /// "Reached this task's limit.": Resume asks for a new "Step limit" and "Active seconds" first.
    public var needsLimits: Bool { state == .budgetExhausted }
    /// "Pebble's change isn't verified yet.": the three decisions (RunPanel "Finish this task").
    public var isHeld: Bool { state == .verificationRequired }
    /// "One step has an uncertain outcome. Check it before resuming.": the uncertain outcomes and paused windows.
    public var needsCheck: Bool { state == .needsReconciliation }
    /// Pebble waits for the person's decision before the task can go on: the Reviews tab lists it.
    public var waitsForDecision: Bool { isHeld || needsCheck }
    /// Pebble's window says this state under the conversation (RunPanel `attention`). A paused task is left to the run
    /// bar, which already says "Paused" and offers Resume (one place for it on the screen).
    public var showsInConversation: Bool { Self.conversationStates.contains(state) }

    /// RunPanel `canResume`.
    public static let resumable: Set<RunState> = [.paused, .stopped, .interrupted, .failed, .budgetExhausted]
    /// RunPanel `attention`, less paused (the run bar's).
    static let conversationStates: Set<RunState> = [
        .interrupted, .failed, .budgetExhausted, .verificationRequired, .needsReconciliation,
    ]
    /// The states a conversation keeps a task for: what it shows, plus what only its menu resumes (paused, stopped).
    static let tracked: Set<RunState> = resumable.union(conversationStates)
}

/// A task's limits for a resume after "Reached this task's limit." (RunPanel's two number fields; runtime.RunLimits).
public struct RunLimits: Sendable, Hashable {
    public var maxSteps: Int
    public var maxSeconds: Int

    public init(maxSteps: Int, maxSeconds: Int) {
        self.maxSteps = maxSteps
        self.maxSeconds = maxSeconds
    }

    /// What Pebble's window fills in first (RunPanel `newLimits`).
    public static let resumeDefaults = RunLimits(maxSteps: 128, maxSeconds: 1800)
    /// "Step limit": 1 to 256 (the field's min and max, and what Pebble accepts).
    public static let stepRange = 1...256
    /// "Active seconds": 1 to 86,400.
    public static let secondRange = 1...86_400

    /// Pebble accepts these (RunLimits.parse refuses anything else: "Choose 1–256 steps and 1–86400 seconds per run.").
    public var isValid: Bool { Self.stepRange.contains(maxSteps) && Self.secondRange.contains(maxSeconds) }

    var json: JSONValue { ["max_steps": .int(maxSteps), "max_seconds": .int(maxSeconds)] }
}

// MARK: - Uncertain outcomes

/// One action Pebble lost track of before it could confirm the outcome (reconcile.py `reconcile_run`: identifiers,
/// verdict and basis only; no paths, output or file contents).
public struct UncertainOutcome: Sendable, Hashable, Identifiable {
    public var id: String { callID }
    public var chatID: ChatID
    public var runID: RunID
    public var callID: String
    /// The tool, as Pebble names it ("WriteFile", "ScreenAct"); nil when Pebble didn't record one.
    public var tool: String?
    /// The broker action's kind ("file", "command"), when there is one.
    public var kind: String?
    /// occurred, not_occurred, diverged or unknown.
    public var verdict: String
    /// Pebble's basis for the verdict, as a code ("file_hash", "no_broker_action").
    public var basis: String

    public init(
        chatID: ChatID, runID: RunID, callID: String, tool: String? = nil, kind: String? = nil, verdict: String,
        basis: String
    ) {
        self.chatID = chatID
        self.runID = runID
        self.callID = callID
        self.tool = tool
        self.kind = kind
        self.verdict = verdict
        self.basis = basis
    }

    init?(json: JSONValue, chatID: ChatID, runID: RunID) {
        guard let callID = json["call_id"]?.string, !callID.isEmpty else { return nil }
        self.init(
            chatID: chatID, runID: runID, callID: callID, tool: json["tool"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            kind: json["kind"]?.string.flatMap { $0.isEmpty ? nil : $0 }, verdict: json["verdict"]?.string ?? "unknown",
            basis: json["basis"]?.string ?? "")
    }

    /// Pebble's readback shows a clean outcome, so it can settle it (ReconcilePanel `settleable`).
    public var canSettleFromReadback: Bool { verdict == "occurred" || verdict == "not_occurred" }
}

/// What `run_readback` found for a task.
public struct ReadbackPage: Sendable, Hashable {
    public var items: [UncertainOutcome]
    /// Another task is running: Pebble reads these back once it ends ("Stop the active run …" is not an error here).
    public var waitsForTask: Bool

    public init(items: [UncertainOutcome], waitsForTask: Bool = false) {
        self.items = items
        self.waitsForTask = waitsForTask
    }
}

/// The person's own report of an uncertain outcome, recorded as unverified ("It happened" / "It did not happen").
public enum OutcomeReport: String, Sendable, Hashable, CaseIterable {
    case occurred
    case didNotOccur = "did_not_occur"
}

// MARK: - Commands

/// A command Pebble started in a conversation (process_list: id, run_id, state, outcome_uncertain,
/// inspection_recorded). Pebble shows no command text here, only its state.
public struct ProcessJob: Sendable, Hashable, Identifiable {
    public var id: String
    public var chatID: ChatID
    public var runID: RunID
    /// admitted, running, succeeded, failed, stopped, limited, refused, unknown.
    public var state: String
    /// Pebble couldn't observe how it ended.
    public var outcomeUncertain: Bool
    /// The person recorded an inspection of it.
    public var inspectionRecorded: Bool

    public init(
        id: String, chatID: ChatID, runID: RunID, state: String, outcomeUncertain: Bool = false,
        inspectionRecorded: Bool = false
    ) {
        self.id = id
        self.chatID = chatID
        self.runID = runID
        self.state = state
        self.outcomeUncertain = outcomeUncertain
        self.inspectionRecorded = inspectionRecorded
    }

    init?(json: JSONValue, chatID: ChatID) {
        guard let id = json["id"]?.string, !id.isEmpty, let run = json["run_id"]?.string, !run.isEmpty else { return nil }
        self.init(
            id: id, chatID: chatID, runID: run, state: json["state"]?.string ?? "unknown",
            outcomeUncertain: flag(json["outcome_uncertain"]), inspectionRecorded: flag(json["inspection_recorded"]))
    }

    /// Still running: Stop command, and typing when its terminal takes it (process_jobs LIVE).
    public var isLive: Bool { state == "admitted" || state == "running" }
    /// "Record my inspection" (ExecutionOutput: an uncertain outcome without an inspection).
    public var needsInspection: Bool { outcomeUncertain && !inspectionRecorded }
    /// "Forget saved command output": settled, and inspected when its outcome was uncertain.
    public var canForgetOutput: Bool { !isLive && (!outcomeUncertain || inspectionRecorded) }
    /// The conversation shows it: running, or with an outcome Pebble couldn't confirm. Settled commands with a known
    /// outcome stay in Pebble's records only.
    public var showsInConversation: Bool { isLive || outcomeUncertain }
}

/// A command's terminal (process_terminal, content-free): whether it takes typing, and whether it echoes.
public struct ProcessTerminal: Sendable, Hashable {
    public var interactive: Bool
    public var live: Bool
    /// false at a password prompt: what the person types is not shown or stored; nil when Pebble can't tell.
    public var echo: Bool?

    public init(interactive: Bool, live: Bool, echo: Bool? = nil) {
        self.interactive = interactive
        self.live = live
        self.echo = echo
    }

    init(json: JSONValue) {
        self.init(interactive: json["interactive"]?.bool ?? false, live: json["live"]?.bool ?? false, echo: json["echo"]?.bool)
    }

    /// "Type into the command" shows (ExecutionOutput: an interactive job that is still live).
    public var takesTyping: Bool { interactive && live }
    /// A password prompt.
    public var isSecret: Bool { echo == false }
}

/// One page of a command's saved output (process_read).
public struct ProcessOutput: Sendable, Hashable {
    /// The command's own output: untrusted text, shown as it is.
    public var text: String
    /// Where the next page starts.
    public var next: Int
    public var more: Bool
    /// The saved output is a partial record of the command.
    public var incomplete: Bool
    /// Terminal control sequences left out of this page.
    public var controlsRemoved: Int
    public var state: String?

    public init(text: String, next: Int, more: Bool, incomplete: Bool, controlsRemoved: Int = 0, state: String? = nil) {
        self.text = text
        self.next = next
        self.more = more
        self.incomplete = incomplete
        self.controlsRemoved = controlsRemoved
        self.state = state
    }

    init(json: JSONValue, after: Int) {
        self.init(
            text: json["untrusted_process_output"]?.string ?? "", next: json["next_after"]?.int ?? after,
            more: flag(json["more"]), incomplete: json["output_complete"]?.bool != true,
            controlsRemoved: max(0, json["controls_removed"]?.int ?? 0), state: json["state"]?.string)
    }
}

/// What the person saw when they inspected a command (ExecutionOutput's "Observed outcome").
public enum ProcessObservation: String, Sendable, Hashable, CaseIterable {
    case stillUncertain = "still_uncertain"
    case effectObserved = "effect_observed"
    case noEffectObserved = "no_effect_observed"
}

/// A key the person may send to a command ("Send Ctrl-C", "Send Ctrl-D"; Enter ends a typed line).
public enum ProcessKey: String, Sendable, Hashable {
    case ctrlC = "ctrl_c"
    case ctrlD = "ctrl_d"
    case enter
}

// MARK: - What Pebble did, with its Undo

/// A card Pebble already acted on that offers an Undo, or one the person undid (App.vue's earlier actions, with the
/// conditions of its four undo buttons).
public struct ActionRecord: Sendable, Hashable, Identifiable {
    public var id: String { "\(chatID)/\(actionID)" }
    public var chatID: ChatID
    public var actionID: ActionID
    public var kind: CardKind
    /// applied, undone (Pebble's action status).
    public var status: String
    /// What it did, as a review card says it ("Change App.vue", "Run npm test").
    public var title: String
    /// The exact thing (the path, the command).
    public var detail: String?
    public var created: Date?
    public var payload: JSONValue
    /// The Undo Pebble's window offers for it, if any.
    public var undo: UndoOffer?

    public init(
        chatID: ChatID, actionID: ActionID, kind: CardKind, status: String, title: String, detail: String? = nil,
        created: Date? = nil, payload: JSONValue = .null, undo: UndoOffer? = nil
    ) {
        self.chatID = chatID
        self.actionID = actionID
        self.kind = kind
        self.status = status
        self.title = title
        self.detail = detail
        self.created = created
        self.payload = payload
        self.undo = undo
    }

    /// The person undid it.
    public var isUndone: Bool { status == "undone" }
}

/// Pebble's four undo buttons on a card it applied (App.vue), each with its method.
public enum UndoOffer: Sendable, Hashable {
    /// "Undo this edit": `undo`, an applied project edit.
    case edit
    /// "Undo this command": `undo`, a command Auto ran without a card, from the copy kept until its task ends.
    case command
    /// "Undo this change": `shell_undo`, a Shell command or file write, from the snapshot taken before it.
    case change(snapshotID: String)
    /// "Propose undo (new reviewed plan)": `git_plan_propose`, a new Git plan that waits for review.
    case gitPlan(receiptID: String)

    /// App.vue's conditions, card by card.
    public init?(kind: CardKind, status: String, payload p: JSONValue) {
        guard status == "applied" else { return nil }
        let result = p["result"]
        switch kind {
        case .edit:
            self = .edit
        case .command where result?["undo"]?.string == "available":
            self = .command
        case .shell, .file:
            let undoable = truthy(result?["snapshot"]?["undoable"]) || truthy(result?["undoable"])
            guard undoable, let id = result?["snapshot"]?["id"]?.string ?? result?["snapshot"]?.string, !id.isEmpty
            else { return nil }
            self = .change(snapshotID: id)
        case .git where p["operation"]?.string != "undo":
            guard let receipt = result?["receipt_id"]?.string, !receipt.isEmpty else { return nil }
            self = .gitPlan(receiptID: receipt)
        default:
            return nil
        }
    }
}

/// How an Undo went, for Pebble's words ("Edit undone", "Some changes could not be undone").
public enum UndoResult: Sendable, Hashable {
    case editUndone
    case commandUndone
    case changeUndone
    case someChangesNotUndone
    case undoPlanReady
}

// MARK: - Always allow

/// One host or folder "Always allow" saves (shell_grant_add {kind, value, scope: "always"}).
public struct AlwaysAllowGrant: Sendable, Hashable {
    /// "hosts" or "folders".
    public var kind: String
    public var value: String

    public init(kind: String, value: String) {
        self.kind = kind
        self.value = value
    }
}

extension ReviewItem {
    /// The card offers "Always allow" (App.vue: a Shell or file card whose payload says `always_offered`).
    public var offersAlwaysAllow: Bool {
        (kind == .shell || kind == .file) && truthy(payload["always_offered"])
    }

    /// What "Always allow" saves, in Pebble's order (App.vue `grantAndApprove`): the card's hosts, then its folders (a
    /// file card's folder is its path without the last part).
    public var alwaysAllowGrants: [AlwaysAllowGrant] {
        let hosts = (payload["hosts"]?.array ?? []).compactMap(\.string)
        let folders: [String]
        if kind == .file {
            let path = payload["path"]?.string ?? ""
            if let slash = path.lastIndex(of: "/") { folders = [String(path[..<slash])] } else { folders = [path] }
        } else {
            folders = (payload["folders"]?.array ?? []).compactMap(\.string)
        }
        return hosts.map { AlwaysAllowGrant(kind: "hosts", value: $0) }
            + folders.filter { !$0.isEmpty }.map { AlwaysAllowGrant(kind: "folders", value: $0) }
    }
}

// MARK: - Continuing on the new model

/// "Continue with the new model": offered in a conversation after the person changed the model there while its newest
/// task is paused, interrupted, failed or out of budget (App.vue `changeModel`). Such a task can't resume on another
/// model; Pebble can continue the conversation as a new run on the new one, once the person approves exactly what
/// would be sent.
public struct HandoffOffer: Sendable, Hashable, Identifiable {
    public var id: ChatID { chatID }
    public var chatID: ChatID
    public var runID: RunID

    public init(chatID: ChatID, runID: RunID) {
        self.chatID = chatID
        self.runID = runID
    }

    /// The states that offer it (App.vue `changeModel`).
    static let states: Set<RunState> = [.paused, .interrupted, .failed, .budgetExhausted]
}

/// What a handoff would send (model_handoff_preview, content-free: counts, message ids, route classes and a
/// fingerprint prefix). Nothing is sent until the person approves this exact plan and starts it.
public struct HandoffPlan: Sendable, Hashable {
    public struct Row: Sendable, Hashable {
        /// "user", "assistant", or Pebble's own records.
        public var role: String
        /// One count per class, in `classes` order.
        public var cells: [Int]
    }

    public var fingerprint: String
    /// The route class the conversation ran on ("cloud:chatgpt", "device", "unknown").
    public var sourceClass: String
    public var destinationClass: String
    /// The first characters of the destination's fingerprint (at most 32, as Pebble's window shows them).
    public var destinationPrefix: String
    /// The classes the messages came from, sorted (the table's columns).
    public var classes: [String]
    /// One row per role, sorted.
    public var rows: [Row]
    /// Messages from another route class, left out.
    public var withheld: [String]
    /// Classes released for this handoff, so sent although they came from another route class.
    public var released: [String]

    public init(
        fingerprint: String, sourceClass: String, destinationClass: String, destinationPrefix: String,
        classes: [String], rows: [Row], withheld: [String] = [], released: [String] = []
    ) {
        self.fingerprint = fingerprint
        self.sourceClass = sourceClass
        self.destinationClass = destinationClass
        self.destinationPrefix = destinationPrefix
        self.classes = classes
        self.rows = rows
        self.withheld = withheld
        self.released = released
    }

    /// ModelHandoff.vue `review()`: nil without a fingerprint ("Pebble could not prepare this handoff.").
    init?(json: JSONValue) {
        guard let fingerprint = json["plan_fingerprint"]?.string, !fingerprint.isEmpty else { return nil }
        let counts = json["counts"]?.object ?? [:]
        let roles = counts.keys.sorted()
        let classes = Set(roles.flatMap { counts[$0]?.object?.keys.map { $0 } ?? [] }).sorted()
        let rows = roles.map { role in
            Row(
                role: role,
                cells: classes.map { name in
                    guard let count = counts[role]?[name]?.int, count >= 0 else { return 0 }
                    return count
                })
        }
        self.init(
            fingerprint: fingerprint, sourceClass: json["source_class"]?.string ?? "",
            destinationClass: json["destination_class"]?.string ?? "",
            destinationPrefix: String((json["destination_fingerprint_prefix"]?.string ?? "").prefix(32)),
            classes: classes, rows: rows, withheld: (json["withheld_ids"]?.array ?? []).compactMap(\.string),
            released: (json["released_classes"]?.array ?? []).compactMap(\.string))
    }

    /// Messages that will be sent: every count in the table.
    public var total: Int { rows.reduce(0) { $0 + $1.cells.reduce(0, +) } }
    /// The messages go up to a cloud model from another class (ModelHandoff `upload`): Pebble warns.
    public var uploads: Bool { sourceClass != destinationClass && destinationClass.hasPrefix("cloud:") }
}

// MARK: - Helpers

/// JavaScript truthiness, as Pebble's window tests payload fields.
func truthy(_ value: JSONValue?) -> Bool {
    switch value {
    case .none, .null?: false
    case .bool(let flag)?: flag
    case .int(let number)?: number != 0
    case .double(let number)?: number != 0 && !number.isNaN
    case .string(let string)?: !string.isEmpty
    case .array?, .object?: true
    }
}

/// A SQLite flag (0 or 1) or a JSON boolean.
private func flag(_ value: JSONValue?) -> Bool { truthy(value) }

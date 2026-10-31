import Foundation
import PebbleProtocol

// Lane Y (fix 8): what the conversation's Details screen reads, tab by tab (Pebble's details drawer: Activity, Task,
// Context, Changes, Tools, Browser). Value types only; RemoteStore+Details builds them from Pebble's answers, with
// Pebble's own field names (read-only Pebble checkout, cited per type). Additions are free; renames go through
// docs/TEAM_BOARD.md first.

// MARK: - Activity

/// A run's steps for Details › Activity: its record and every activity item the phone received, with Pebble's own
/// count of its steps, so the screen can say when the two differ (UX audit U-45).
public struct RunSteps: Sendable, Hashable, Identifiable {
    public var id: RunID { details.id }
    public var details: RunDetails
    /// Pebble's count of the run's steps (get_chat's `counts`, kept for the newest 20 settled runs: its tool, check
    /// and agent rows). Nil while the run works, or when Pebble kept none.
    public var pebbleCount: Int?
    /// Every item Pebble had was read; false when the phone stopped at its page limit.
    public var isComplete: Bool

    public init(details: RunDetails, pebbleCount: Int? = nil, isComplete: Bool = true) {
        self.details = details
        self.pebbleCount = pebbleCount
        self.isComplete = isComplete
    }

    /// Pebble's steps among the items (app.py `_run_counts`, activity.ts `tally`): tool, check and agent rows.
    public static let stepKinds: Set<String> = ["tool", "check", "child"]

    /// The steps the phone lists, counted as Pebble counts them.
    public var listedSteps: Int { details.items.filter { Self.stepKinds.contains($0.kind) }.count }
    /// Retries among the items (activity.ts `tally`).
    public var listedRetries: Int { details.items.filter { $0.kind == "retry" }.count }
    /// Seconds spent waiting for the person (activity.ts `tally`: approval rows' durations).
    public var listedWait: Double {
        details.items.filter { $0.kind == "approval" }.compactMap(\.duration).reduce(0, +)
    }

    /// Pebble counted more steps than reached the phone (U-45): the screen says so in words.
    public var missingSteps: Int? {
        guard let pebbleCount, pebbleCount > listedSteps else { return nil }
        return pebbleCount - listedSteps
    }
}

// MARK: - Context (context_inspector.py `inspect`, `compact`; ContextPanel.vue)

/// How full a task's model window is (`context_inspect`). Pebble sends sizes, never a percentage: the Mac's ring works
/// it out as `round(used / window × 100)`, capped at 999 (App.vue, activity.ts).
public struct ContextUse: Sendable, Hashable {
    public struct Category: Sendable, Hashable, Identifiable {
        /// system, tool_schemas, memory, project_host, conversation, tool_results, framing.
        public var id: String
        public var tokens: Int
        public var messages: Int?

        public init(id: String, tokens: Int, messages: Int? = nil) {
            self.id = id
            self.tokens = tokens
            self.messages = messages
        }
    }

    public var runID: RunID?
    /// last_request, checkpoint or none.
    public var basis: String
    public var isLive: Bool
    /// The request's size with Pebble's calibration (`used`, else `total`).
    public var used: Int?
    /// The window's size (`window.tokens`); nil when Pebble doesn't know it.
    public var window: Int?
    public var free: Int?
    public var over: Int?
    public var categories: [Category]
    /// Whether "Compact…" can run now, and Pebble's reason code when not: live, not_latest, finished, not_resumable,
    /// no_window, between_tools.
    public var canCompact: Bool
    public var compactReason: String?

    public init(
        runID: RunID? = nil, basis: String, isLive: Bool = false, used: Int? = nil, window: Int? = nil, free: Int? = nil,
        over: Int? = nil, categories: [Category] = [], canCompact: Bool = false, compactReason: String? = nil
    ) {
        self.runID = runID
        self.basis = basis
        self.isLive = isLive
        self.used = used
        self.window = window
        self.free = free
        self.over = over
        self.categories = categories
        self.canCompact = canCompact
        self.compactReason = compactReason
    }

    /// "{n}% of context used", as the Mac's ring counts it; nil without a request or a known window.
    public var percent: Int? {
        guard basis != "none", let used, let window, window > 0 else { return nil }
        return min(999, Int((Double(used) / Double(window) * 100).rounded()))
    }

    public init?(json: JSONValue) {
        guard let basis = json["basis"]?.string else { return nil }
        let compact = json["compact"]
        self.init(
            runID: json["run_id"]?.string, basis: basis, isLive: json["live"]?.bool ?? false,
            used: json["used"]?.int ?? json["total"]?.int, window: json["window"]?["tokens"]?.int,
            free: json["free"]?.int, over: json["over"]?.int,
            categories: (json["categories"]?.array ?? []).compactMap { item in
                guard let id = item["id"]?.string, let tokens = item["tokens"]?.int else { return nil }
                return Category(id: id, tokens: tokens, messages: item["messages"]?.int)
            },
            canCompact: compact?["available"]?.bool ?? false, compactReason: compact?["reason"]?.string)
    }
}

/// What "Compact now" did (`context_compact`'s receipt).
public struct CompactOutcome: Sendable, Hashable {
    /// compacted, already_fits or fresh_window.
    public var status: String
    public var archivedMessages: Int
    public var archivedToolResults: Int
    public var freedTokens: Int?
    /// The receipt's first eight characters, as the Mac's notice shows it.
    public var receipt: String?
    /// The window after compacting, when Pebble sent it.
    public var context: ContextUse?

    public init(
        status: String, archivedMessages: Int = 0, archivedToolResults: Int = 0, freedTokens: Int? = nil,
        receipt: String? = nil, context: ContextUse? = nil
    ) {
        self.status = status
        self.archivedMessages = archivedMessages
        self.archivedToolResults = archivedToolResults
        self.freedTokens = freedTokens
        self.receipt = receipt
        self.context = context
    }

    public init?(json: JSONValue) {
        guard let status = json["status"]?.string else { return nil }
        self.init(
            status: status, archivedMessages: json["archived"]?["messages"]?.int ?? 0,
            archivedToolResults: json["archived"]?["tool_results"]?.int ?? 0,
            freedTokens: json["tokens"]?["freed"]?.int, receipt: json["receipt_id"]?.string.map { String($0.prefix(8)) },
            context: json["context"].flatMap(ContextUse.init(json:)))
    }
}

// MARK: - Changes: rewinding files (rewind.py; RewindPanel.vue)

/// What a rewind to one step of a task would put back (`rewind_preview`). Apply sends its `digest` back.
public struct RewindPlan: Sendable, Hashable {
    public struct File: Sendable, Hashable, Identifiable {
        public var id: String { path }
        public var path: String
        /// revert, refused, kept or unchanged.
        public var status: String
        /// Pebble's words for why it is left alone (rewind.py `REASONS`); nil for a file it restores.
        public var detail: String?
        /// The task's steps that wrote it.
        public var steps: [Int]
        public var diff: String?
        public var diffCut: Bool

        public init(path: String, status: String, detail: String? = nil, steps: [Int] = [], diff: String? = nil, diffCut: Bool = false) {
            self.path = path
            self.status = status
            self.detail = detail
            self.steps = steps
            self.diff = diff
            self.diffCut = diffCut
        }
    }

    /// Something after the step that a rewind never undoes (a command, a message, a Git change).
    public struct Effect: Sendable, Hashable, Identifiable {
        public var id: String
        /// command, connector, git, app, agent, view or companion.
        public var kind: String
        public var step: Int?
        public var label: String
        public var outcome: String?
        public var note: String?

        public init(id: String, kind: String, step: Int? = nil, label: String, outcome: String? = nil, note: String? = nil) {
            self.id = id
            self.kind = kind
            self.step = step
            self.label = label
            self.outcome = outcome
            self.note = note
        }
    }

    /// A step the person can rewind to, with what the task wrote there.
    public struct Point: Sendable, Hashable, Identifiable {
        public var id: Int { step }
        public var step: Int
        public var files: [String]
        public var effects: Int

        public init(step: Int, files: [String] = [], effects: Int = 0) {
            self.step = step
            self.files = files
            self.effects = effects
        }
    }

    public var chatID: ChatID
    public var runID: RunID
    /// The step it rewinds to: 0 is before the task.
    public var step: Int
    /// How many steps the task took.
    public var steps: Int
    public var digest: String
    public var files: [File]
    public var effects: [Effect]
    public var effectsOmitted: Int
    public var timeline: [Point]
    /// This plan undoes the last rewind.
    public var undoesLastRewind: Bool
    /// The step to review for undoing the last rewind, when one was applied and isn't the step chosen here.
    public var lastRewindUndoStep: Int?

    public init(
        chatID: ChatID, runID: RunID, step: Int, steps: Int, digest: String, files: [File] = [], effects: [Effect] = [],
        effectsOmitted: Int = 0, timeline: [Point] = [], undoesLastRewind: Bool = false, lastRewindUndoStep: Int? = nil
    ) {
        self.chatID = chatID
        self.runID = runID
        self.step = step
        self.steps = steps
        self.digest = digest
        self.files = files
        self.effects = effects
        self.effectsOmitted = effectsOmitted
        self.timeline = timeline
        self.undoesLastRewind = undoesLastRewind
        self.lastRewindUndoStep = lastRewindUndoStep
    }

    /// The files a rewind would restore ("Rewind N files").
    public var restoring: Int { files.filter { $0.status == "revert" }.count }

    /// The steps the picker offers (RewindPanel.vue): before the task, this one, the last, and every step that wrote.
    public var choices: [Int] {
        Array(Set([0, step, steps] + timeline.map(\.step))).filter { $0 >= 0 && $0 <= max(steps, step) }.sorted()
    }

    public init?(json: JSONValue) {
        guard let chat = json["chat_id"]?.string, let run = json["run_id"]?.string, let step = json["step"]?.int,
            let digest = json["digest"]?.string
        else { return nil }
        let applied = (json["rewinds"]?.array ?? []).last { $0["applied"]?.bool == true }
        let undoStep = applied?["previous_step"]?.int
        self.init(
            chatID: chat, runID: run, step: step, steps: json["steps"]?.int ?? step, digest: digest,
            files: (json["files"]?.array ?? []).compactMap { file in
                guard let path = file["path"]?.string, let status = file["status"]?.string else { return nil }
                return File(
                    path: path, status: status, detail: file["detail"]?.string,
                    steps: (file["steps"]?.array ?? []).compactMap(\.int), diff: file["diff"]?.string,
                    diffCut: file["diff_truncated"]?.bool ?? false)
            },
            effects: (json["effects"]?.array ?? []).enumerated().compactMap { index, effect in
                guard let kind = effect["kind"]?.string else { return nil }
                let id = effect["call_id"]?.string ?? effect["action_id"]?.string ?? "\(index)"
                return Effect(
                    id: "\(index)-\(id)", kind: kind, step: effect["step"]?.int,
                    label: effect["label"]?.string ?? effect["tool"]?.string ?? kind, outcome: effect["outcome_text"]?.string,
                    note: effect["note"]?.string)
            },
            effectsOmitted: json["effects_omitted"]?.int ?? 0,
            timeline: (json["timeline"]?.array ?? []).compactMap { point in
                guard let step = point["step"]?.int else { return nil }
                return Point(step: step, files: (point["files"]?.array ?? []).compactMap(\.string), effects: point["effects"]?.int ?? 0)
            },
            undoesLastRewind: json["reverses"]?.string != nil,
            lastRewindUndoStep: undoStep.flatMap { $0 == step ? nil : $0 })
    }
}

/// What a rewind did (`rewind_apply`): each file's outcome, read back.
public struct RewindResult: Sendable, Hashable {
    public struct File: Sendable, Hashable, Identifiable {
        public var id: String { path }
        public var path: String
        /// reverted, diverged, uncertain, refused, kept or unchanged.
        public var status: String
        public var detail: String?
        public var verified: Bool

        public init(path: String, status: String, detail: String? = nil, verified: Bool = false) {
            self.path = path
            self.status = status
            self.detail = detail
            self.verified = verified
        }
    }

    public var files: [File]
    public var restored: Int

    public init(files: [File], restored: Int) {
        self.files = files
        self.restored = restored
    }

    public init?(json: JSONValue) {
        guard let list = json["files"]?.array else { return nil }
        let files = list.compactMap { file -> File? in
            guard let path = file["path"]?.string, let status = file["status"]?.string else { return nil }
            return File(path: path, status: status, detail: file["detail"]?.string, verified: file["verified"]?.bool ?? false)
        }
        self.init(files: files, restored: json["counts"]?["reverted"]?.int ?? files.filter { $0.status == "reverted" }.count)
    }
}

// MARK: - Task: the goal (goals.py; GoalPanel.vue)

/// A goal's progress (goals.py `progress`).
public struct GoalProgress: Sendable, Hashable {
    public var criteriaMet: Int
    public var criteriaTotal: Int
    public var proposed: Int
    public var stepsDone: Int
    public var stepsTotal: Int

    public init(criteriaMet: Int = 0, criteriaTotal: Int = 0, proposed: Int = 0, stepsDone: Int = 0, stepsTotal: Int = 0) {
        self.criteriaMet = criteriaMet
        self.criteriaTotal = criteriaTotal
        self.proposed = proposed
        self.stepsDone = stepsDone
        self.stepsTotal = stepsTotal
    }

    init(json: JSONValue?) {
        self.init(
            criteriaMet: json?["criteria_met"]?.int ?? 0, criteriaTotal: json?["criteria_total"]?.int ?? 0,
            proposed: json?["candidates"]?.int ?? 0, stepsDone: json?["steps_completed"]?.int ?? 0,
            stepsTotal: json?["steps_total"]?.int ?? 0)
    }
}

/// A goal as `goal_list` lists it, newest first.
public struct GoalSummary: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// active, paused, blocked, done or abandoned.
    public var state: String
    public var revision: Int
    public var updated: Date?
    public var progress: GoalProgress
    /// The first thing holding it up, in Pebble's words ("Needs your review").
    public var blocker: String?

    public init(
        id: String, title: String, state: String, revision: Int, updated: Date? = nil, progress: GoalProgress = .init(),
        blocker: String? = nil
    ) {
        self.id = id
        self.title = title
        self.state = state
        self.revision = revision
        self.updated = updated
        self.progress = progress
        self.blocker = blocker
    }

    /// Still the conversation's current goal (GoalPanel.vue: active, paused or blocked).
    public var isCurrent: Bool { ["active", "paused", "blocked"].contains(state) }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.string, let title = json["title"]?.string, let state = json["state"]?.string,
            let revision = json["revision"]?.int
        else { return nil }
        self.init(
            id: id, title: title, state: state, revision: revision, updated: unixDate(json["updated"]),
            progress: GoalProgress(json: json["progress"]), blocker: json["blocker"]?["label"]?.string)
    }
}

/// A completion criterion (goals.py: kind human_check or evidence; status candidate, open, met, unmet, rejected).
public struct GoalCriterion: Sendable, Hashable, Identifiable {
    public var id: String
    public var text: String
    public var kind: String
    public var status: String
    /// human (the person wrote it) or agent (Pebble proposed it).
    public var origin: String
    /// human or host (task evidence), once checked.
    public var checkedBy: String?
    /// Pebble's words on what it waits for, or why it isn't met.
    public var detail: String?

    public init(
        id: String, text: String, kind: String = "human_check", status: String = "open", origin: String = "human",
        checkedBy: String? = nil, detail: String? = nil
    ) {
        self.id = id
        self.text = text
        self.kind = kind
        self.status = status
        self.origin = origin
        self.checkedBy = checkedBy
        self.detail = detail
    }

    public var isEvidence: Bool { kind == "evidence" }
    /// Pebble proposed it and the person hasn't decided yet.
    public var isProposed: Bool { status == "candidate" }
}

/// A goal in full (`goal_get`).
public struct GoalRecord: Sendable, Hashable, Identifiable {
    public struct Step: Sendable, Hashable, Identifiable {
        public var id: String
        public var title: String
        /// pending, in_progress, blocked or completed.
        public var status: String
        /// Lane T: the steps it comes after (goals.py `depends_on`; GoalPanel.vue's "After").
        public var after: [String]
        /// Lane T: what blocks it, while it is blocked (goals.py: kind text, failure, question or approval).
        public var blocker: StepBlocker?
        /// Lane T: pending, and every step it comes after is completed.
        public var isReady: Bool

        public init(
            id: String, title: String, status: String, after: [String] = [], blocker: StepBlocker? = nil,
            isReady: Bool = false
        ) {
            self.id = id
            self.title = title
            self.status = status
            self.after = after
            self.blocker = blocker
            self.isReady = isReady
        }

        public var isBlocked: Bool { status == "blocked" }
    }

    public var id: String
    public var chatID: ChatID
    public var title: String
    public var state: String
    public var revision: Int
    public var criteria: [GoalCriterion]
    public var steps: [Step]
    /// What holds it up, in Pebble's words.
    public var blockers: [String]
    public var progress: GoalProgress
    /// Pebble's note on what a goal record is.
    public var note: String?
    /// Lane T: what holds it up in full (GoalPanel.vue's Blockers table), in Pebble's order; `blockers` is their
    /// labels.
    public var blockerItems: [GoalBlocker]

    public init(
        id: String, chatID: ChatID, title: String, state: String, revision: Int, criteria: [GoalCriterion] = [],
        steps: [Step] = [], blockers: [String] = [], progress: GoalProgress = .init(), note: String? = nil,
        blockerItems: [GoalBlocker] = []
    ) {
        self.id = id
        self.chatID = chatID
        self.title = title
        self.state = state
        self.revision = revision
        self.criteria = criteria
        self.steps = steps
        self.blockers = blockers
        self.progress = progress
        self.note = note
        self.blockerItems = blockerItems
    }

    public var isCurrent: Bool { ["active", "paused", "blocked"].contains(state) }
    public var isPaused: Bool { state == "paused" }

    public init?(json: JSONValue, chatID fallback: ChatID) {
        guard let id = json["id"]?.string, let title = json["title"]?.string, let state = json["state"]?.string,
            let revision = json["revision"]?.int
        else { return nil }
        self.init(
            id: id, chatID: json["chat_id"]?.string ?? fallback, title: title, state: state, revision: revision,
            criteria: (json["criteria"]?.array ?? []).compactMap { item in
                guard let id = item["id"]?.string, let text = item["text"]?.string else { return nil }
                return GoalCriterion(
                    id: id, text: text, kind: item["kind"]?.string ?? "human_check", status: item["status"]?.string ?? "open",
                    origin: item["origin"]?.string ?? "human", checkedBy: item["checked_by"]?.string,
                    detail: item["detail"]?.string)
            },
            steps: (json["steps"]?.array ?? []).compactMap { item in
                guard let id = item["id"]?.string, let title = item["title"]?.string else { return nil }
                return Step(
                    id: id, title: title, status: item["status"]?.string ?? "pending",
                    after: (item["depends_on"]?.array ?? []).compactMap(\.string),
                    blocker: StepBlocker(json: item["blocker"]), isReady: item["ready"]?.bool ?? false)
            },
            blockers: (json["blockers"]?.array ?? []).compactMap { $0["label"]?.string },
            progress: GoalProgress(json: json["progress"]), note: json["note"]?.string,
            blockerItems: (json["blockers"]?.array ?? []).compactMap(GoalBlocker.init(json:)))
    }
}

// MARK: - Task: agents (agent_tree.py, agent_manager.py; AgentPanel.vue)

/// A helper agent in a task's tree (`agent_list` nodes, ordered as Pebble lists them; the tree is `parentID`).
public struct AgentNode: Sendable, Hashable, Identifiable {
    public var id: String
    public var runID: RunID
    public var parentID: String?
    public var name: String?
    public var task: String
    public var depth: Int
    /// queued, running, waiting_parent, waiting_input, completed, failed, interrupted, stopped, budget_exhausted.
    public var status: String
    /// What it answered, when it finished with text.
    public var result: String?
    public var tokens: Int?
    public var seconds: Double?

    public init(
        id: String, runID: RunID, parentID: String? = nil, name: String? = nil, task: String, depth: Int = 1,
        status: String, result: String? = nil, tokens: Int? = nil, seconds: Double? = nil
    ) {
        self.id = id
        self.runID = runID
        self.parentID = parentID
        self.name = name
        self.task = task
        self.depth = depth
        self.status = status
        self.result = result
        self.tokens = tokens
        self.seconds = seconds
    }

    /// Still working or waiting (agent_tree.py ACTIVE): Send input works only then.
    public var isActive: Bool { ["queued", "running", "waiting_parent", "waiting_input"].contains(status) }
    /// Cancel works while it is active or interrupted (AgentPanel.vue).
    public var canCancel: Bool { isActive || status == "interrupted" }

    public init?(json: JSONValue, runID fallback: RunID) {
        guard let id = json["agent_id"]?.string ?? json["id"]?.string, let status = json["status"]?.string else {
            return nil
        }
        let result = json["result"]
        self.init(
            id: id, runID: json["run_id"]?.string ?? fallback, parentID: json["parent_id"]?.string,
            name: json["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }, task: json["task"]?.string ?? "",
            depth: json["depth"]?.int ?? 1, status: status, result: result?.string ?? result?["text"]?.string,
            tokens: json["charged_tokens"]?.int, seconds: json["elapsed"]?.double)
    }
}

// MARK: - Browser (browser_bridge.py, browser_session.py, screen_session.py; PebbleBrowser.vue)

/// Pebble for Chrome, as `browser_extension_status` reports it. The pairing code it carries stays on the Mac: the
/// phone never reads it.
public struct ChromeStatus: Sendable, Hashable {
    /// A tab the person shared from Chrome's toolbar.
    public struct SharedTab: Sendable, Hashable, Identifiable {
        public var id: String
        public var origin: String
        /// The page's own title (page text: never permission).
        public var title: String
        /// tab (just this visit) or site (kept for this site).
        public var scope: String
        /// ready, away or handback.
        public var state: String
        public var acting: Bool
        public var granted: Bool

        public init(
            id: String, origin: String, title: String = "", scope: String = "tab", state: String = "ready",
            acting: Bool = false, granted: Bool = false
        ) {
            self.id = id
            self.origin = origin
            self.title = title
            self.scope = scope
            self.state = state
            self.acting = acting
            self.granted = granted
        }
    }

    public var connected: Bool
    public var present: Bool
    public var paused: Bool
    public var paired: Bool
    /// A pairing code waits on the Mac.
    public var pairing: Bool
    /// Pairing paused after wrong codes.
    public var pairingLocked: Bool
    /// Chrome's helper files are in place.
    public var helperInstalled: Bool
    public var chromeVersion: String?
    public var extensionVersion: String?
    public var sharedTabs: [SharedTab]

    public init(
        connected: Bool = false, present: Bool = false, paused: Bool = false, paired: Bool = false, pairing: Bool = false,
        pairingLocked: Bool = false, helperInstalled: Bool = false, chromeVersion: String? = nil,
        extensionVersion: String? = nil, sharedTabs: [SharedTab] = []
    ) {
        self.connected = connected
        self.present = present
        self.paused = paused
        self.paired = paired
        self.pairing = pairing
        self.pairingLocked = pairingLocked
        self.helperInstalled = helperInstalled
        self.chromeVersion = chromeVersion
        self.extensionVersion = extensionVersion
        self.sharedTabs = sharedTabs
    }

    public init?(json: JSONValue) {
        guard let ext = json["extension"]?.object else { return nil }
        let pairing = json["pairing"]
        let hosts = json["host"]?.object?.values.contains { $0.bool == true } ?? false  // lint-copy: allow (Pebble's field name)
        self.init(
            connected: ext["connected"]?.bool ?? false, present: ext["present"]?.bool ?? false,
            paused: json["paused"]?.bool ?? false, paired: pairing?["paired"]?.bool ?? false,
            pairing: pairing?["pending"]?.object != nil, pairingLocked: (pairing?["locked_for"]?.int ?? 0) > 0,
            helperInstalled: hosts, chromeVersion: ext["chrome"]?.string, extensionVersion: ext["version"]?.string,
            sharedTabs: (json["shared_tabs"]?.array ?? []).compactMap { tab in
                guard let id = tab["tab_id"]?.string, let origin = tab["origin"]?.string else { return nil }
                return SharedTab(
                    id: id, origin: origin, title: tab["title"]?.string ?? "", scope: tab["scope"]?.string ?? "tab",
                    state: tab["state"]?.string ?? "ready", acting: tab["acting"]?.bool ?? false,
                    granted: tab["granted"]?.bool ?? false)
            })
    }
}

/// Pebble's own browser (`browser_status`).
public struct PebbleBrowserStatus: Sendable, Hashable {
    public var running: Bool
    public var available: Bool
    public var product: String?
    /// Pebble's words for why it can't start, when it can't.
    public var reason: String?

    public init(running: Bool, available: Bool, product: String? = nil, reason: String? = nil) {
        self.running = running
        self.available = available
        self.product = product
        self.reason = reason
    }

    public init?(json: JSONValue) {
        guard let running = json["running"]?.bool else { return nil }
        self.init(
            running: running, available: json["available"]?.bool ?? running, product: json["product"]?.string,
            reason: json["reason"]?.string)
    }
}

/// A tab open in Pebble's browser (`browser_tabs`).
public struct BrowserTab: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// Its site; nil when it isn't a website (so it can't be granted).
    public var origin: String?

    public init(id: String, title: String, origin: String? = nil) {
        self.id = id
        self.title = title
        self.origin = origin
    }

    public init?(json: JSONValue) {
        guard let id = json["tab_id"]?.string else { return nil }
        self.init(id: id, title: json["title"]?.string ?? "", origin: json["origin"]?.string)
    }
}

/// A tab the person lets Pebble use (`screen_session_grant` with a browser target).
public struct TabGrant: Sendable, Hashable {
    /// "chrome" (the person's Chrome) or "pebble" (Pebble's own browser).
    public var profile: String
    public var tabID: String
    /// Exact sites ("https://docs.github.com"), 1 to 8.
    public var origins: [String]
    /// Pebble's action names, grouped as the Mac's form groups them.
    public var actions: [String]
    public var minutes: Int
    /// Chrome only.
    public var screenshots: Bool

    public init(profile: String, tabID: String, origins: [String], actions: [String], minutes: Int, screenshots: Bool = false) {
        self.profile = profile
        self.tabID = tabID
        self.origins = origins
        self.actions = actions
        self.minutes = minutes
        self.screenshots = screenshots
    }

    /// The form's three choices (PebbleBrowser.vue): look around, fill in, press buttons.
    public static let look = ["focus", "scroll", "expand", "collapse"]
    public static let fill = ["select", "toggle", "type"]
    public static let press = ["press", "enter"]

    func params(chat: ChatID, enableScreen: Bool) -> JSONValue {
        var target: [String: JSONValue] = [
            "kind": "browser", "profile": .string(profile), "tab_id": .string(tabID), "origins": .array(origins.map(JSONValue.string)),
        ]
        if profile != "chrome" { target["profile"] = "pebble" }
        return [
            "id": .string(chat), "target": .object(target), "actions": .array(actions.map(JSONValue.string)),
            "ttl": .int(max(1, min(1800, minutes * 60))), "screenshots": .bool(profile == "chrome" && screenshots),
            "enable_screen": .bool(enableScreen),
        ]
    }
}

/// What a tab grant came to: granted, or Pebble asks first to turn on Screen control (nothing was recorded yet).
public enum TabGrantOutcome: Sendable, Hashable {
    case granted(pending: Bool)
    /// Pebble's own words, and whether "Turn on Screen control and grant" can work now.
    case needsScreenControl(message: String, canTurnOn: Bool)
}

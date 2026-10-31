import Foundation
import PebbleProtocol

// Lane Y (fix 8): the calls behind the conversation's Details screen. Calls and params are Pebble's own (read-only
// Pebble checkout, cited per call); Pebble's lambda routes take exactly their named params, so nothing else is sent.
// Reads made on a screen's own account are quiet (`readsQuietly`): they never ask for Face ID by themselves.

extension RemoteStore {
    // MARK: Activity (run_activity.py `read`)

    /// Pebble sends at most this many activity items a page (run_activity.py `PAGE_ITEMS`).
    public static let activityPageItems = 400
    /// The phone reads at most this many pages of a run's activity (2,000 items) before it says what it left out.
    public static let activityPages = 5

    /// A run's record and every step Pebble kept, in order, with Pebble's own count (Details › Activity). The record
    /// comes from `run_list` (`run_get` carries every tool's whole result); the items from `run_activity`, page by page
    /// after its `next` cursor. A running item comes back on every page, so items are kept by `seq`, the newest copy.
    public func runSteps(_ run: RunID, in chat: ChatID) async throws -> RunSteps {
        var record: LiveRunRecord?
        if offers("run_list"), let rows = try? await client.call("run_list", ["id": .string(chat)]) {
            record = (rows.array ?? []).first { $0["id"]?.string == run }.flatMap(LiveRunRecord.init(json:))
        }
        if record == nil, let row = world.runs[run]?.row {
            let note = PersonNote.filter(row.error)
            record = LiveRunRecord(
                id: row.id, chatID: row.chatID, state: row.state, steps: row.steps, elapsed: row.elapsed,
                note: note.isEmpty ? nil : note, created: row.created, updated: row.updated)
        }
        guard let record else { throw unreadable() }
        var bySeq: [Int: RunActivityItem] = [:]
        var reasoning: String?
        var header: WorkHeader?
        var summary: WorkSummary?
        var after = 0
        var complete = false
        for _ in 0..<Self.activityPages {
            let page = try await answer("run_activity", ["run_id": .string(run), "after": .int(after)])
            let items = (page["items"]?.array ?? []).compactMap(RunActivityItem.init(json:))
            for item in items { bySeq[item.seq] = item }
            if let text = page["reasoning"]?["text"]?.string { reasoning = text.isEmpty ? nil : text }
            // Lane G: the work view's header and, once the run settled, its summary (the newest page's).
            header = WorkHeader(json: page["header"]) ?? header
            summary = WorkSummary(json: page["summary"]) ?? summary
            let next = page["next"]?.int ?? after
            if items.count < Self.activityPageItems || next <= after {
                complete = true
                break
            }
            after = next
        }
        let details = RunDetails(
            run: record, items: bySeq.values.sorted { $0.seq < $1.seq }, reasoning: reasoning, header: header,
            summary: summary)
        return RunSteps(details: details, pebbleCount: world.runs[run]?.row.counts?.steps, isComplete: complete)
    }
}

/// What Face ID says for the Details screen's guarded steps. Names come from Pebble (a goal's title, an agent's name),
/// so each is one plain line (StoreWords.detail).
public enum DetailsWords {
    public static func rewindReason(files: Int) -> String {
        files == 1 ? "Rewind 1 file on your Mac" : "Rewind \(files) files on your Mac"
    }
    public static func goalDoneReason(_ title: String) -> String { "Mark the goal \u{201C}\(StoreWords.detail(title))\u{201D} done" }
    public static func goalAbandonReason(_ title: String) -> String {
        "Abandon the goal \u{201C}\(StoreWords.detail(title))\u{201D}"
    }
    public static func criterionReason(_ text: String) -> String { "Settle the criterion \u{201C}\(StoreWords.detail(text))\u{201D}" }
    public static func cancelAgentReason(_ name: String) -> String {
        "Cancel \u{201C}\(StoreWords.detail(name))\u{201D} and the agents under it"
    }
    public static let startBrowserReason = "Start Pebble's own browser on your Mac"
    public static func grantTabReason(_ site: String) -> String { "Let Pebble use a tab on \(StoreWords.detail(site))" }
}

extension RemoteStore {
    // MARK: Context (context_inspector.py: `chat_id`, `run_id`; the bridge writes `surface` itself)

    /// How full a task's window is. A read, but the bridge wants the unlock for it: the screen asks only when it may.
    public func contextUse(in chat: ChatID, run: RunID?) async throws -> ContextUse {
        var params: [String: JSONValue] = ["chat_id": .string(chat)]
        if let run { params["run_id"] = .string(run) }
        guard let use = ContextUse(json: try await answer("context_inspect", .object(params))) else { throw unreadable() }
        return use
    }

    /// "Compact now": Pebble compacts the conversation's latest task window between turns (`chat_id` only).
    public func compactContext(in chat: ChatID) async throws -> CompactOutcome {
        guard let outcome = CompactOutcome(json: try await answer("context_compact", ["chat_id": .string(chat)])) else {
            throw unreadable()
        }
        return outcome
    }

    // MARK: Changes (rewind.py: preview `chat_id, run_id, step`; apply adds the preview's `digest`)

    /// What rewinding the task's files to `step` would put back (0 is before the task). Nothing changes.
    public func rewindPreview(in chat: ChatID, run: RunID, step: Int) async throws -> RewindPlan {
        let params: JSONValue = ["chat_id": .string(chat), "run_id": .string(run), "step": .int(step)]
        guard let plan = RewindPlan(json: try await answer("rewind_preview", params)) else { throw unreadable() }
        return plan
    }

    /// Rewinds the files the person reviewed. Asks for Face ID (contract 3.6: `rewind_apply`).
    public func rewind(_ plan: RewindPlan) async throws -> RewindResult {
        let params: JSONValue = [
            "chat_id": .string(plan.chatID), "run_id": .string(plan.runID), "step": .int(plan.step),
            "digest": .string(plan.digest),
        ]
        let answer = try await answerElevated("rewind_apply", params, reason: DetailsWords.rewindReason(files: plan.restoring))
        guard let result = RewindResult(json: answer) else { throw unreadable() }
        return result
    }

    // MARK: Task: the goal (goals.py; every change names the revision the person saw)

    /// The conversation's goals, newest first (`goal_list`).
    public func goals(in chat: ChatID) async throws -> [GoalSummary] {
        let list = try await answer("goal_list", ["chat_id": .string(chat), "limit": 20])
        return (list.array ?? []).compactMap(GoalSummary.init(json:))
    }

    /// One goal in full (`goal_get`).
    public func goal(_ id: String, in chat: ChatID) async throws -> GoalRecord {
        try record(try await answer("goal_get", ["chat_id": .string(chat), "goal_id": .string(id)]), chat: chat)
    }

    /// "Start goal": the conversation's goal (a record: it starts no task and grants no permission).
    public func createGoal(_ title: String, in chat: ChatID) async throws -> GoalRecord {
        try record(try await answer("goal_create", ["chat_id": .string(chat), "title": .string(title)]), chat: chat)
    }

    /// "Pause" or "Resume" the goal record.
    public func setGoalPaused(_ goal: GoalRecord, _ paused: Bool) async throws -> GoalRecord {
        try record(try await answer("goal_state", goalParams(goal, ["state": .string(paused ? "paused" : "active")])), chat: goal.chatID)
    }

    /// "Mark done" or "Abandon": settling a goal is the person's own decision (Findings F3, F5), so it asks for Face ID
    /// whether or not the bridge lists it.
    public func settleGoal(_ goal: GoalRecord, done: Bool) async throws -> GoalRecord {
        let reason = done ? DetailsWords.goalDoneReason(goal.title) : DetailsWords.goalAbandonReason(goal.title)
        let answer = try await act(
            "goal_state", goalParams(goal, ["state": .string(done ? "done" : "abandoned")]), reason: reason, elevate: true)
        return try record(answer, chat: goal.chatID)
    }

    /// "Mark met", "Mark not met" and "Verify receipts" (task evidence checks itself). With Face ID (F5).
    public func checkCriterion(_ criterion: GoalCriterion, met: Bool, of goal: GoalRecord) async throws -> GoalRecord {
        let params = goalParams(goal, ["criterion_id": .string(criterion.id), "met": .bool(met)])
        let answer = try await act(
            "goal_criterion_check", params, reason: DetailsWords.criterionReason(criterion.text), elevate: true)
        return try record(answer, chat: goal.chatID)
    }

    /// "Accept" or "Reject" a criterion Pebble proposed. With Face ID (F5).
    public func reviewCriterion(_ criterion: GoalCriterion, accept: Bool, of goal: GoalRecord) async throws -> GoalRecord {
        let params = goalParams(goal, ["criterion_id": .string(criterion.id), "decision": .string(accept ? "accept" : "reject")])
        let answer = try await act(
            "goal_criterion_review", params, reason: DetailsWords.criterionReason(criterion.text), elevate: true)
        return try record(answer, chat: goal.chatID)
    }

    /// "Add criterion", checked by the person (`human_check`) or by task evidence (`evidence`).
    public func addCriterion(_ text: String, evidence: Bool, to goal: GoalRecord) async throws -> GoalRecord {
        let params = goalParams(goal, ["text": .string(text), "kind": .string(evidence ? "evidence" : "human_check")])
        return try record(try await answer("goal_criterion_add", params), chat: goal.chatID)
    }

    /// "Continue goal": a new task toward the goal (Pebble refuses while one runs elsewhere).
    public func continueGoal(_ goal: GoalRecord) async throws {
        _ = try await answer("goal_continue", ["chat_id": .string(goal.chatID), "goal_id": .string(goal.id)])
    }

    private func goalParams(_ goal: GoalRecord, _ more: [String: JSONValue]) -> JSONValue {
        var params: [String: JSONValue] = [
            "chat_id": .string(goal.chatID), "goal_id": .string(goal.id), "revision": .int(goal.revision),
        ]
        params.merge(more) { _, new in new }
        return .object(params)
    }

    private func record(_ json: JSONValue, chat: ChatID) throws -> GoalRecord {
        guard let goal = GoalRecord(json: json, chatID: chat) else { throw unreadable() }
        return goal
    }

    // MARK: Task: agents (app.py `agent_*`: `chat_id`, `run_id` of the root task, `agent_id`)

    /// The task's helper agents, in Pebble's order (`agent_list`).
    public func agents(in chat: ChatID, run: RunID) async throws -> [AgentNode] {
        let result = try await answer("agent_list", ["chat_id": .string(chat), "run_id": .string(run)])
        return (result["nodes"]?.array ?? []).compactMap { AgentNode(json: $0, runID: run) }
    }

    /// "Send input" to a working agent.
    public func steer(_ agent: AgentNode, in chat: ChatID, text: String) async throws {
        _ = try await answer(
            "agent_steer",
            ["chat_id": .string(chat), "run_id": .string(agent.runID), "agent_id": .string(agent.id), "text": .string(text)])
    }

    /// "Cancel agent and descendants". It can't be taken back, so it asks for Face ID (Findings F3).
    public func cancel(_ agent: AgentNode, in chat: ChatID) async throws {
        let params: JSONValue = ["chat_id": .string(chat), "run_id": .string(agent.runID), "agent_id": .string(agent.id)]
        _ = try await act("agent_cancel", params, reason: DetailsWords.cancelAgentReason(agent.name ?? agent.task), elevate: true)
    }

    // MARK: Browser (app.py `browser_*`: no params; `screen_session_grant(id, target, actions, ttl, screenshots, enable_screen)`)

    /// Pebble for Chrome's state. Pebble's pairing code is in the answer; the phone never keeps or shows it.
    public func chromeStatus() async throws -> ChromeStatus {
        guard let status = ChromeStatus(json: try await answer("browser_extension_status", [:])) else { throw unreadable() }
        return status
    }

    /// "Pause" (true) or "Resume" (false) Pebble in Chrome; the number of tab sessions it changed.
    @discardableResult
    public func pauseChrome(_ pause: Bool) async throws -> Int {
        let result = try await answer(pause ? "browser_extension_pause" : "browser_extension_resume", [:])
        requestList(.screenSessions)
        return result["sessions"]?.int ?? 0
    }

    /// "Stop Pebble in Chrome": every Chrome session ends at once. The shared tabs Pebble let go of.
    @discardableResult
    public func stopChrome() async throws -> Int {
        let result = try await answer("browser_extension_stop", [:])
        requestList(.screenSessions)
        return result["shares_cleared"]?.int ?? 0
    }

    public func pebbleBrowserStatus() async throws -> PebbleBrowserStatus {
        guard let status = PebbleBrowserStatus(json: try await answer("browser_status", [:])) else { throw unreadable() }
        return status
    }

    /// "Start Pebble's browser": it opens on the Mac's screen, so it asks for Face ID (proposal v0.5).
    public func startPebbleBrowser() async throws -> PebbleBrowserStatus {
        let answer = try await act("browser_start", [:], reason: DetailsWords.startBrowserReason, elevate: true)
        guard let status = PebbleBrowserStatus(json: answer) else { throw unreadable() }
        return status
    }

    /// "Stop Pebble's browser"; its tab sessions end with it.
    public func stopPebbleBrowser() async throws {
        _ = try await answer("browser_stop", [:])
        requestList(.screenSessions)
    }

    /// The tabs open in Pebble's browser.
    public func pebbleBrowserTabs() async throws -> [BrowserTab] {
        (try await answer("browser_tabs", [:]).array ?? []).compactMap(BrowserTab.init(json:))
    }

    /// "Grant this tab": lets Pebble use one tab on the sites chosen, for the time chosen. Asks for Face ID (3.6). When
    /// Screen control is off, Pebble records nothing and asks first; `enableScreen` answers yes.
    public func grant(_ tab: TabGrant, in chat: ChatID, enableScreen: Bool = false) async throws -> TabGrantOutcome {
        let answer = try await act(
            "screen_session_grant", tab.params(chat: chat, enableScreen: enableScreen),
            reason: DetailsWords.grantTabReason(tab.origins.first ?? ""), elevate: true)
        requestList(.screenSessions)
        if answer["status"]?.string == "needs_screen_permission" {
            return .needsScreenControl(
                message: answer["message"]?.string ?? "", canTurnOn: answer["enable"]?["available"]?.bool ?? false)
        }
        return .granted(pending: answer["pending"]?.bool ?? false)
    }

    // MARK: Tools (job_api.py `job_list(id)`, screen_session.py `screen_sessions(id)`)

    /// This conversation's schedules and the windows and tabs it may use, read into the store's lists (the Settings
    /// tab's lists across conversations stay one source).
    public func loadTools(in chat: ChatID) async {
        if offers("job_list"), let result = try? await client.call("job_list", ["id": .string(chat)]) {
            let mine = (result["jobs"]?.array ?? []).compactMap {
                ScheduleItem(json: $0, chatID: chat, chatTitle: world.title(of: chat))
            }
            var all = schedules.filter { $0.chatID != chat } + mine
            all.sort { ($0.nextRun ?? .distantFuture, $0.name) < ($1.nextRun ?? .distantFuture, $1.name) }
            if schedules != all { schedules = all }
        }
        if offers("screen_sessions"), let result = try? await client.call("screen_sessions", ["id": .string(chat)]) {
            let now = clock()
            let live = (result.array ?? []).compactMap { ScreenSession(json: $0, chatID: chat) }.filter { $0.isLive(at: now) }
            var all = screenSessions.filter { $0.chatID != chat } + live
            all.sort { ($0.expires ?? .distantFuture, $0.id) < ($1.expires ?? .distantFuture, $1.id) }
            if screenSessions != all { screenSessions = all }
        }
    }
}

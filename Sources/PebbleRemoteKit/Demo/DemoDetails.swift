import Foundation
import PebbleProtocol

// Lane Y (fix 8): what the demo's Details screen shows, tab by tab, so the UI audit sees each one. Every answer has the
// shape Pebble gives (read-only Pebble checkout, cited per call), and the demo offers only what the bridge offers.

extension DemoData {
    /// Pebble's reasoning summaries for the demo's earlier runs (run_activity `reasoning.text`).
    static let reasoning: [String: String] = [
        "r-commits": """
            The person wants a short summary of last week's work. I'll read the commit log first, then look for \
            anything that changes behaviour people rely on, and group the changes by area rather than by commit.
            """
    ]
}

/// The demo's goals, agents, task windows, rewinds and browsers, with the shapes Pebble's routes answer (goals.py,
/// agent_tree.py, context_inspector.py, rewind.py, browser_bridge.py, browser_session.py, screen_session.py).
struct DemoDetails: Sendable {
    /// Goals by conversation, newest first: a current goal for "Add a dark mode toggle", and an earlier one.
    var goals: [String: [JSONValue]] = [:]
    /// Helper agents by run.
    var agents: [String: [JSONValue]] = [:]
    /// Runs whose window was compacted.
    var compacted: Set<String> = []
    /// Runs whose files were rewound (to before the task).
    var rewound: Set<String> = []
    var chromePaused = false
    var chromeTabShared = true
    var browserRunning = true
    var goalSeq = 2

    init(now: Date) {
        let at = now.timeIntervalSince1970
        goals[DemoData.themeChat] = [
            [
                "id": "g-dark", "chat_id": .string(DemoData.themeChat), "origin": "human", "title": "Dark mode ships in Settings",
                "revision": 4, "state": "blocked", "created": .double(at - 30 * 60), "updated": .double(at - 2 * 60),
                "criteria": [
                    [
                        "id": "c1", "text": "The toggle follows the system until you choose", "kind": "human_check",
                        "status": "met", "origin": "human", "checked_by": "human", "evidence": [], "detail": .null,
                    ],
                    [
                        "id": "c2", "text": "Tests pass on main", "kind": "evidence", "status": "open", "origin": "human",
                        "checked_by": .null, "evidence": [], "detail": "waiting for step s2",
                    ],
                    [
                        "id": "c3", "text": "The choice is remembered after a restart", "kind": "human_check",
                        "status": "candidate", "origin": "agent", "checked_by": .null, "evidence": [], "detail": .null,
                    ],
                ],
                // Lane T: steps and blockers as goals.py `_snapshot` and `_blockers` give them.
                "steps": [
                    [
                        "id": "s1", "title": "Add the toggle to Settings", "status": "completed", "depends_on": [],
                        "blocker": .null, "ready": false,
                    ],
                    [
                        "id": "s2", "title": "Run the settings tests", "status": "pending", "depends_on": ["s1"],
                        "blocker": .null, "ready": true,
                    ],
                    [
                        "id": "s3", "title": "Check the contrast in both themes", "status": "blocked",
                        "depends_on": ["s1"], "ready": false,
                        "blocker": ["kind": "text", "ref": "Waiting for the new colours from design", "active": true],
                    ],
                ],
                "blockers": [
                    [
                        "kind": "text", "ref": "s3", "label": "Blocked by you", "step_id": "s3",
                        "detail": "Waiting for the new colours from design", "detail_origin": "human",
                    ],
                    [
                        "kind": "failure", "ref": .string(DemoData.themeRun), "label": "Latest run needs verification",
                        "run_id": .string(DemoData.themeRun),
                    ],
                ],
                "runs": [.string(DemoData.themeRun)], "authorization": "none",
                "note": "Goal records are operational records, not memory. Evidence links are recorded, resolved and current task records; they do not prove semantic correctness or grant permission.",
            ],
            [
                "id": "g-system", "chat_id": .string(DemoData.themeChat), "origin": "human",
                "title": "The theme follows the system", "revision": 6, "state": "done", "created": .double(at - 3 * 86400),
                "updated": .double(at - 2 * 86400),
                "criteria": [
                    [
                        "id": "c1", "text": "Light and dark both read well", "kind": "human_check", "status": "met",
                        "origin": "human", "checked_by": "human", "evidence": [], "detail": .null,
                    ]
                ],
                "steps": [], "blockers": [], "runs": [], "authorization": "none", "note": .null,
            ],
        ]
        goals[DemoData.readmeChat] = [DemoGoals.readmeGoal(at: at)]  // lane T: a step waits for the npm test review
        agents[DemoData.readmeRun] = [
            [
                "id": "a-links", "agent_id": "a-links", "run_id": .string(DemoData.readmeRun), "parent_id": .null,
                "name": "Link checker", "task": "Check that every link in README.md opens and goes where its text says.",
                "depth": 1, "status": "running", "result": .null, "charged_tokens": 4180, "elapsed": 21.4,
            ],
            [
                "id": "a-proof", "agent_id": "a-proof", "run_id": .string(DemoData.readmeRun), "parent_id": .null,
                "name": "Proofreader", "task": "Proofread the new install steps and the quick start.", "depth": 1,
                "status": "completed",
                "result": ["text": "Two fixes: \u{201C}an Mac\u{201D} in step 2, and a missing full stop in the quick start.", "checks": "Parent verification required."],
                "charged_tokens": 2950, "elapsed": 12.9,
            ],
        ]
    }

    static func progress(_ goal: JSONValue) -> JSONValue {
        let criteria = goal["criteria"]?.array ?? []
        let accepted = criteria.filter { !["candidate", "rejected"].contains($0["status"]?.string ?? "") }
        let steps = goal["steps"]?.array ?? []
        return [
            "criteria_met": .int(accepted.filter { $0["status"]?.string == "met" }.count), "criteria_total": .int(accepted.count),
            "candidates": .int(criteria.filter { $0["status"]?.string == "candidate" }.count),
            "steps_completed": .int(steps.filter { $0["status"]?.string == "completed" }.count), "steps_total": .int(steps.count),
        ]
    }

    static func snapshot(_ goal: JSONValue) -> JSONValue {
        guard case .object(var object) = goal else { return goal }
        object["progress"] = progress(goal)
        return .object(object)
    }

    static func listRow(_ goal: JSONValue) -> JSONValue {
        [
            "id": goal["id"] ?? .null, "title": goal["title"] ?? .null, "state": goal["state"] ?? .null,
            "revision": goal["revision"] ?? .null, "created": goal["created"] ?? .null, "updated": goal["updated"] ?? .null,
            "progress": progress(goal), "blockers": .int(goal["blockers"]?.array?.count ?? 0),
            "blocker": goal["blockers"]?.array?.first ?? .null,
        ]
    }
}

extension DemoClient {
    /// The Details screen's methods, or nil for another method. Pebble's refusals word for word.
    func detailsAnswer(_ method: String, _ params: JSONValue, proven: Bool) throws -> JSONValue? {
        switch method {
        case "goal_list":
            let chat = try detailsChat(params, key: "chat_id")
            return .array((details.goals[chat] ?? []).map(DemoDetails.listRow))
        case "goal_get":
            let chat = try detailsChat(params, key: "chat_id")
            return DemoDetails.snapshot(try findGoal(params, in: chat).goal)
        case "goal_create": return try createGoal(params)
        case "goal_state", "goal_criterion_check", "goal_criterion_review", "goal_criterion_add":
            return try changeGoal(method, params)
        case "goal_continue":
            let chat = try detailsChat(params, key: "chat_id")
            let (goal, _) = try findGoal(params, in: chat)
            if goal["state"]?.string == "paused" { throw refusal("Resume this goal before continuing it.") }
            let title = goal["title"]?.string ?? ""
            let text = "Continue working toward the goal \u{201C}\(title)\u{201D}. Use the goal record for its criteria, steps and blockers."
            return try send(["id": .string(chat), "text": .string(text)])
        case "agent_list":
            let run = params["run_id"]?.string ?? ""
            guard runs[run] != nil else { throw refusal("Root run not found in this conversation.") }
            return ["root_run_id": .string(run), "nodes": .array(details.agents[run] ?? []), "budget": [:]]
        case "agent_steer":
            let (run, index) = try agent(params)
            guard ["queued", "running", "waiting_parent", "waiting_input"].contains(details.agents[run]?[index]["status"]?.string ?? "")
            else { throw refusal("This agent is no longer accepting follow-ups.") }
            guard let text = params["text"]?.string, !text.isEmpty else { throw refusal("Agent text must be nonempty and bounded.") }
            return ["agent_id": details.agents[run]?[index]["id"] ?? .null, "status": "accepted", "origin": "human"]
        case "agent_cancel":
            let (run, index) = try agent(params)
            var list = details.agents[run] ?? []
            let id = list[index]["id"]?.string ?? ""
            var stopped: [JSONValue] = []
            for position in list.indices where list[position]["id"]?.string == id || list[position]["parent_id"]?.string == id {
                if case .object(var node) = list[position],
                    ["queued", "running", "waiting_parent", "waiting_input"].contains(node["status"]?.string ?? "")
                {
                    node["status"] = "stopped"
                    list[position] = .object(node)
                }
                stopped.append(list[position]["id"] ?? .null)
            }
            details.agents[run] = list
            return ["agent_ids": .array(stopped), "status": "stopped", "origin": "agent"]
        case "context_inspect": return try contextJSON(params)
        case "context_compact":
            let chat = try detailsChat(params, key: "chat_id")
            guard let run = runs.values.filter({ $0.chatID == chat }).max(by: { $0.created < $1.created }) else {
                throw refusal("This conversation has no task window to compact yet.")
            }
            if run.isLive { throw refusal("A task is running. Compact between turns: wait for it to finish, or pause it first.") }
            if run.state == "completed" { return ["status": "fresh_window", "chat_id": .string(chat), "run_id": .string(run.id)] }
            details.compacted.insert(run.id)
            return [
                "status": "compacted", "chat_id": .string(chat), "run_id": .string(run.id),
                "archived": ["messages": 18, "tool_results": 7], "tokens": ["before": 165_900, "after": 104_700, "freed": 61_200],
                "context": try contextJSON(["chat_id": .string(chat), "run_id": .string(run.id)]),
            ]
        case "rewind_preview": return try rewindJSON(params)
        case "rewind_apply":
            let plan = try rewindJSON(params)
            guard params["digest"]?.string == plan["digest"]?.string else {
                throw refusal("The files, effects or permissions changed since this preview. Nothing was written. Review the new preview.")
            }
            let run = params["run_id"]?.string ?? ""
            let restoring = (plan["files"]?.array ?? []).filter { $0["status"]?.string == "revert" }
            if params["step"]?.int == 0 { details.rewound.insert(run) } else { details.rewound.remove(run) }
            return [
                "rewind_id": "rw-1", "chat_id": params["chat_id"] ?? .null, "run_id": .string(run), "step": params["step"] ?? 0,
                "files": .array(restoring.map { ["path": $0["path"] ?? .null, "status": "reverted", "detail": .null, "verified": true] }),
                "counts": ["reverted": .int(restoring.count), "verified": .int(restoring.count), "refused": 0, "uncertain": 0],
            ]
        case "browser_extension_status": return chromeJSON()
        case "browser_extension_pause", "browser_extension_resume":
            details.chromePaused = method == "browser_extension_pause"
            return ["paused": .bool(details.chromePaused), "sessions": 0]
        case "browser_extension_stop":
            let cleared = details.chromeTabShared ? 1 : 0
            details.chromeTabShared = false
            return ["stopped": true, "shares_cleared": .int(cleared), "revoked_sessions": 0]
        case "browser_status": return browserJSON()
        case "browser_start":
            details.browserRunning = true
            return browserJSON()
        case "browser_stop":
            let was = details.browserRunning
            details.browserRunning = false
            var revoked = 0
            for (chat, list) in workflows.sessions {
                workflows.sessions[chat] = list.map { session in
                    guard case .object(var object) = session, object["target"]?["profile"]?.string == "pebble",
                        ["active", "handoff", "interrupted"].contains(object["state"]?.string ?? "")
                    else { return session }
                    revoked += 1
                    object["state"] = "revoked"
                    return .object(object)
                }
            }
            return ["revoked_sessions": .int(revoked), "stopped": .bool(was)]
        case "browser_tabs":
            guard details.browserRunning else {
                throw refusal("That kind of window or tab is not supported here. Pebble's own browser is not running; start it first.")
            }
            return [["tab_id": "1001", "title": "Signing in with GitHub", "origin": "https://docs.github.com", "url": "https://docs.github.com/en/get-started"]]
        case "screen_session_grant": return try grantTab(params)
        case "research_sources":
            // The weather reply's two sources: a page to open, and one without a secure address (named instead).
            guard params["run_id"]?.string == "r-weather" else { return ["sources": [], "omitted_sources": 0, "conflicts": []] }
            return [
                "sources": [
                    [
                        "source_id": "S1", "kind": "web", "title": "Lisbon: hourly forecast", "domain": "ipma.pt",
                        "url": "https://www.ipma.pt/en/otempo/prev.localidade.hora/",
                    ],
                    [
                        "source_id": "S2", "kind": "web", "title": "Lisbon weekend outlook", "domain": "weather.example",
                        "url": "http://weather.example/lisbon",
                    ],
                ],
                "omitted_sources": 0, "conflicts": [], "authorization": "none",
            ]
        default: return nil
        }
    }

    private func detailsChat(_ params: JSONValue, key: String) throws -> String {
        guard let chat = params[key]?.string, chatIndex(chat) != nil else { throw refusal("Conversation not found.") }
        return chat
    }

    private func findGoal(_ params: JSONValue, in chat: String) throws -> (goal: JSONValue, index: Int) {
        let id = params["goal_id"]?.string
        guard let index = details.goals[chat]?.firstIndex(where: { $0["id"]?.string == id }), let goal = details.goals[chat]?[index]
        else { throw refusal("Goal not found in this conversation.") }
        return (goal, index)
    }

    private func createGoal(_ params: JSONValue) throws -> JSONValue {
        let chat = try detailsChat(params, key: "chat_id")
        guard let title = params["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count < 240 else {
            throw refusal("Enter nonempty text under 240 characters.")
        }
        if (details.goals[chat] ?? []).contains(where: { ["active", "paused", "blocked"].contains($0["state"]?.string ?? "") }) {
            throw refusal("This conversation already has a current goal. Mark it done or abandon it first.")
        }
        details.goalSeq += 1
        let at = now().timeIntervalSince1970
        let goal: JSONValue = [
            "id": .string("g-\(details.goalSeq)"), "chat_id": .string(chat), "origin": "human", "title": .string(title),
            "revision": 1, "state": "active", "created": .double(at), "updated": .double(at), "criteria": [], "steps": [],
            "blockers": [], "runs": [], "authorization": "none", "note": .null,
        ]
        details.goals[chat, default: []].insert(goal, at: 0)
        return DemoDetails.snapshot(goal)
    }

    /// goal_state, goal_criterion_check, goal_criterion_review and goal_criterion_add, each naming the revision seen.
    private func changeGoal(_ method: String, _ params: JSONValue) throws -> JSONValue {
        let chat = try detailsChat(params, key: "chat_id")
        let (goal, index) = try findGoal(params, in: chat)
        guard case .object(var object) = goal else { throw refusal("Goal not found in this conversation.") }
        let state = object["state"]?.string ?? ""
        if ["done", "abandoned"].contains(state) { throw refusal("This goal is \(state); its record is closed.") }
        let revision = object["revision"]?.int ?? 0
        guard params["revision"]?.int == revision else { throw refusal("This goal changed (revision \(revision)). Refresh it before editing.") }
        var criteria = object["criteria"]?.array ?? []
        let criterion = params["criterion_id"]?.string
        let position = criteria.firstIndex { $0["id"]?.string == criterion }
        switch method {
        case "goal_state":
            switch params["state"]?.string {
            case "paused":
                if state == "paused" { throw refusal("This goal is already paused.") }
                object["state"] = "paused"
            case "active":
                guard state == "paused" else { throw refusal("Only a paused goal can be resumed.") }
                object["state"] = (object["blockers"]?.array ?? []).isEmpty ? "active" : "blocked"
            case "abandoned": object["state"] = "abandoned"
            case "done":
                var reasons: [String] = []
                let accepted = criteria.filter { !["candidate", "rejected"].contains($0["status"]?.string ?? "") }
                if accepted.isEmpty { reasons.append("add at least one completion criterion") }
                let proposed = criteria.filter { $0["status"]?.string == "candidate" }.count
                if proposed > 0 { reasons.append("accept or reject \(proposed) proposed \(proposed == 1 ? "criterion" : "criteria")") }
                for item in accepted where item["status"]?.string != "met" {
                    let need = item["kind"]?.string == "human_check" ? "your check" : item["detail"]?.string ?? "current task records"
                    reasons.append("criterion \(item["id"]?.string ?? "") is \(item["status"]?.string ?? "open") (\(need))")
                }
                let blockers = object["blockers"]?.array?.count ?? 0
                if blockers > 0 { reasons.append("resolve \(blockers) blocker\(blockers == 1 ? "" : "s")") }
                if !reasons.isEmpty { throw refusal("This goal is not done yet: " + reasons.joined(separator: "; ") + ".") }
                object["state"] = "done"
            default: throw refusal("Choose active, paused, done or abandoned.")
            }
        case "goal_criterion_check":
            guard let position, case .object(var item) = criteria[position] else { throw refusal("Criterion not found in this goal.") }
            if item["status"]?.string == "candidate" { throw refusal("Accept this proposed criterion before checking it.") }
            if item["status"]?.string == "rejected" { throw refusal("This criterion was rejected.") }
            guard let met = params["met"]?.bool else { throw refusal("met must be a boolean.") }
            if met, item["kind"]?.string == "evidence" {
                throw refusal("Criterion \(item["id"]?.string ?? "") has no evidence yet: \(item["detail"]?.string ?? "waiting for a step").")
            }
            item["status"] = met ? "met" : "unmet"
            item["checked_by"] = "human"
            item["detail"] = met ? .null : "marked not met by you"
            criteria[position] = .object(item)
            object["criteria"] = .array(criteria)
        case "goal_criterion_review":
            guard let position, case .object(var item) = criteria[position] else { throw refusal("Criterion not found in this goal.") }
            guard item["status"]?.string == "candidate" else { throw refusal("Only a proposed criterion can be accepted or rejected.") }
            switch params["decision"]?.string {
            case "accept": item["status"] = "open"
            case "reject": item["status"] = "rejected"
            default: throw refusal("Accept or reject the proposed criterion.")
            }
            criteria[position] = .object(item)
            object["criteria"] = .array(criteria)
        default:
            guard let text = params["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count < 500 else {
                throw refusal("Enter nonempty text under 500 characters.")
            }
            guard criteria.count < 12 else { throw refusal("A goal holds up to 12 criteria.") }
            if criteria.contains(where: { $0["text"]?.string == text }) { throw refusal("This goal already has that criterion.") }
            let kind = params["kind"]?.string ?? "human_check"
            guard ["human_check", "evidence"].contains(kind) else { throw refusal("Choose a human_check or evidence criterion.") }
            criteria.append([
                "id": .string("c\(criteria.count + 1)"), "text": .string(text), "kind": .string(kind), "status": "open",
                "origin": "human", "checked_by": .null, "evidence": [],
                "detail": kind == "evidence" ? "link a step to it in the Goal panel" : .null,
            ])
            object["criteria"] = .array(criteria)
        }
        object["revision"] = .int(revision + 1)
        object["updated"] = .double(now().timeIntervalSince1970)
        details.goals[chat]?[index] = .object(object)
        emit("goal", ["chat_id": .string(chat), "goal_id": object["id"] ?? .null, "revision": .int(revision + 1), "state": object["state"] ?? .null])
        return DemoDetails.snapshot(.object(object))
    }

    private func agent(_ params: JSONValue) throws -> (run: String, index: Int) {
        let run = params["run_id"]?.string ?? ""
        guard runs[run] != nil else { throw refusal("Root run not found in this conversation.") }
        guard let index = details.agents[run]?.firstIndex(where: { $0["id"]?.string == params["agent_id"]?.string }) else {
            throw refusal("Agent not found in this root tree.")
        }
        return (run, index)
    }

    /// A run's window: a long project task fills most of it, a short one little.
    private func contextJSON(_ params: JSONValue) throws -> JSONValue {
        let chat = try detailsChat(params, key: "chat_id")
        let run =
            params["run_id"]?.string.flatMap { runs[$0] }
            ?? runs.values.filter { $0.chatID == chat }.max(by: { $0.created < $1.created })
        guard let run, run.chatID == chat else { throw refusal("Run not found in this conversation.") }
        let window = 272_000
        var used = min(240_000, 18_000 + run.steps * 16_500)
        if details.compacted.contains(run.id) { used -= 61_200 }
        let parts: [(String, Int)] = [
            ("system", 6_200), ("tool_schemas", 21_400), ("memory", 1_800), ("project_host", used / 6),
            ("conversation", used / 5), ("tool_results", 0), ("framing", 900),
        ]
        let known = parts.reduce(0) { $0 + $1.1 }
        let categories = parts.map { id, tokens -> JSONValue in
            ["id": .string(id), "tokens": .int(id == "tool_results" ? max(0, used - known) : tokens), "messages": .int(id == "conversation" ? run.steps * 2 : 0)]
        }
        let reason: JSONValue = run.isLive ? "live" : run.state == "completed" ? "finished" : .null
        return [
            "chat_id": .string(chat), "run_id": .string(run.id), "latest_run_id": .string(run.id), "run_state": .string(run.state),
            "steps": .int(run.steps), "basis": run.isLive ? "checkpoint" : "last_request", "live": .bool(run.isLive),
            "total": .int(used), "used": .int(used), "free": .int(max(0, window - used)), "over": 0,
            "window": ["tokens": .int(window), "source": "last_projection"], "categories": .array(categories),
            "compact": ["available": .bool(reason == .null), "reason": reason], "authorization": "none",
        ]
    }

    /// The theme task wrote one file (the demo's applied edit) and ran one command after it.
    private func rewindJSON(_ params: JSONValue) throws -> JSONValue {
        let chat = try detailsChat(params, key: "chat_id")
        guard let runID = params["run_id"]?.string, let run = runs[runID], run.chatID == chat else {
            throw refusal("Run not found in this conversation.")
        }
        guard let step = params["step"]?.int, step >= 0, step <= run.steps else {
            throw refusal("Choose a step from 0 (before this task) to \(run.steps).")
        }
        if run.isLive { throw refusal("Pause or stop this task before rewinding its files.") }
        let rewound = details.rewound.contains(runID)
        var files: [JSONValue] = []
        var effects: [JSONValue] = []
        var timeline: [JSONValue] = []
        if runID == DemoData.themeRun {
            let restore = step < 2 && !rewound || step >= 2 && rewound
            files = [
                [
                    "path": "src/settings/ThemeToggle.tsx", "status": restore ? "revert" : "unchanged",
                    "reason": restore ? .null : "unchanged", "detail": restore ? .null : "Already as it was after that step.",
                    "steps": [2],
                    "diff": restore
                        ? (rewound
                            ? "--- a/src/settings/ThemeToggle.tsx (now)\n+++ b/src/settings/ThemeToggle.tsx (after rewind)\n@@ -1,3 +1,9 @@\n export function ThemeToggle() {\n-  return null;\n+  const [theme, setTheme] = useTheme();\n+  return (\n+    <Switch checked={theme === 'dark'} onChange={(on) => setTheme(on ? 'dark' : 'light')}>\n+      Dark mode\n+    </Switch>\n+  );\n }"
                            : "--- a/src/settings/ThemeToggle.tsx (now)\n+++ b/src/settings/ThemeToggle.tsx (after rewind)\n@@ -1,9 +1,3 @@\n export function ThemeToggle() {\n-  const [theme, setTheme] = useTheme();\n-  return (\n-    <Switch checked={theme === 'dark'} onChange={(on) => setTheme(on ? 'dark' : 'light')}>\n-      Dark mode\n-    </Switch>\n-  );\n+  return null;\n }")
                        : .null,
                    "diff_truncated": false,
                ]
            ]
            if step < 3 {
                effects = [
                    [
                        "kind": "command", "tool": "Shell", "step": 3, "call_id": "call-lint", "label": "npm run lint",
                        "outcome": "occurred", "outcome_text": "It ran", "reverted": false,
                        "note": "Not reverted. A command is never undone or run again.",
                    ]
                ]
            }
            timeline = [["step": 2, "files": ["src/settings/ThemeToggle.tsx"], "effects": 0], ["step": 3, "files": [], "effects": 1]]
        }
        let digest = String(repeating: rewound ? "b" : "a", count: 63) + String(step % 10)
        return [
            "chat_id": .string(chat), "run_id": .string(runID), "step": .int(step), "steps": .int(run.steps),
            "state": .string(run.state), "digest": .string(digest), "files": .array(files), "effects": .array(effects),
            "effects_omitted": 0, "timeline": .array(timeline),
            "rewinds": rewound ? [["rewind_id": "rw-1", "step": 0, "previous_step": .int(run.steps), "reverses": .null, "applied": true]] : [],
            "reverses": rewound && step == run.steps ? "rw-1" : .null,
        ]
    }

    private func chromeJSON() -> JSONValue {
        [
            "extension": [
                "connected": true, "present": true, "version": "1.9.29", "chrome": "131.0.6778.86", "browser": "chrome",
                "protocol": "pebble-browser/2", "debugger_blocked": false,
            ],
            "paused": .bool(details.chromePaused), "pairing": ["paired": true, "paired_at": .null, "locked_for": .null, "pending": .null],
            "bridge": ["listening": true, "error": .null], "site_grants": [], "owned_tabs": [],
            "shared_tabs": details.chromeTabShared
                ? [
                    [
                        "tab_id": "1188", "origin": "https://github.com", "title": "Pull requests \u{00B7} pebble-web",
                        "url": .null, "scope": "tab", "state": details.chromePaused ? "handback" : "ready", "acting": false,
                        "granted": false,
                    ]
                ] : [],
            "authorization": "none",
        ]
    }

    private func browserJSON() -> JSONValue {
        [
            "running": .bool(details.browserRunning), "instance": .null, "product": "Chromium 131",
            "profile_exists": true, "available": true, "reason": .null,
        ]
    }

    /// A tab grant: Screen control off asks first (nothing recorded), as Pebble does.
    private func grantTab(_ params: JSONValue) throws -> JSONValue {
        let chat = try detailsChat(params, key: "id")
        guard let target = params["target"], target["kind"]?.string == "browser", let tab = target["tab_id"]?.string,
            let origins = target["origins"]?.array, !origins.isEmpty
        else {
            throw refusal("The screen request is malformed.")
        }
        let enable = params["enable_screen"]?.bool ?? false
        let screenOn = settings["permissions"]?["tools"]?["screen"]?.bool ?? false
        let kind = "tab"
        if !screenOn && !enable {
            return [
                "status": "needs_screen_permission", "granted": false,
                "message": .string(
                    "Screen control is off in Permissions, so Pebble cannot use this \(kind) yet. "
                        + (activeRun == nil
                            ? "Turn it on and grant the \(kind) in one step; nothing else in Permissions changes."
                            : "Screen control can be turned on once the current task finishes, because permissions never change under a running task.")),
                "enable": ["permission": "screen", "enable_screen": true, "available": .bool(activeRun == nil), "label": "Turn on Screen control and grant"],
                "authorization": "none",
            ]
        }
        if !screenOn, activeRun != nil {
            throw refusal(
                "Screen control can be turned on once the current task finishes, because permissions never change under a running task.")
        }
        if !screenOn, case .object(var permissions) = settings["permissions"] ?? .null, case .object(var tools) = permissions["tools"] ?? .null {
            tools["screen"] = true
            permissions["tools"] = .object(tools)
            settings["permissions"] = .object(permissions)
            emit("settings", [:])
        }
        let ttl = max(1, min(1800, params["ttl"]?.int ?? 900))
        let pending = activeChat != chat
        let id = "session-grant-\(nextID())"
        let session: JSONValue = [
            "session_id": .string(id), "run_id": .null, "kind": "browser",
            "target": ["kind": "browser", "profile": target["profile"] ?? "pebble", "tab_id": .string(tab), "origins": .array(origins)],
            "actions": params["actions"] ?? [], "state": "active", "reason": .null,
            "expires": .double(now().timeIntervalSince1970 + Double(ttl)), "pending": .bool(pending),
        ]
        workflows.sessions[chat, default: []].append(session)
        return [
            "session_id": .string(id), "chat_id": .string(chat), "run_id": .null, "kind": "browser", "target": session["target"] ?? .null,
            "actions": params["actions"] ?? [], "state": "active", "expires_at": session["expires"] ?? .null, "ttl_seconds": .int(ttl),
            "pending": .bool(pending), "screen_enabled": true, "screenshots": params["screenshots"] ?? false,
        ]
    }
}

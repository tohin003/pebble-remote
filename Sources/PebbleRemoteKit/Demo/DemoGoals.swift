import Foundation
import PebbleProtocol

// Lane T (2026-10-31): the demo's goal edits and helper agents in full, with the shapes and refusals of goals.py and
// agent_manager.py `get` (read-only Pebble checkout, cited per function). Pure functions over the goal's JSON, so the
// demo client only stores what they return.

enum DemoGoals {
    /// "Update the README for 2.0" works toward a goal whose second step waits for the `npm test` card: its blocker's
    /// Review opens that card.
    static func readmeGoal(at: Double) -> JSONValue {
        [
            "id": "g-readme", "chat_id": .string(DemoData.readmeChat), "origin": "human",
            "title": "The README is ready for 2.0", "revision": 3, "state": "blocked", "created": .double(at - 40 * 60),
            "updated": .double(at - 6 * 60),
            "criteria": [
                [
                    "id": "c1", "text": "Every link opens", "kind": "evidence", "status": "open", "origin": "human",
                    "checked_by": .null, "evidence": [], "detail": "waiting for step s2",
                ],
                [
                    "id": "c2", "text": "The install steps work on a new Mac", "kind": "human_check", "status": "open",
                    "origin": "human", "checked_by": .null, "evidence": [], "detail": .null,
                ],
            ],
            "steps": [
                [
                    "id": "s1", "title": "Rewrite the install steps", "status": "completed", "depends_on": [],
                    "blocker": .null, "ready": false,
                ],
                [
                    "id": "s2", "title": "Run the docs tests", "status": "blocked", "depends_on": ["s1"],
                    "blocker": ["kind": "approval", "ref": .string(DemoData.readmeCard), "active": true],
                    "ready": false,
                ],
                [
                    "id": "s3", "title": "Proofread the quick start", "status": "pending", "depends_on": ["s1"],
                    "blocker": .null, "ready": true,
                ],
            ],
            "blockers": [
                [
                    "kind": "approval", "ref": .string(DemoData.readmeCard), "label": "Needs your review",
                    "run_id": .string(DemoData.readmeRun), "step_id": "s2",
                ]
            ],
            "runs": [.string(DemoData.readmeRun)], "authorization": "none",
            "note": .string(
                "Goal records are operational records, not memory. Evidence links are recorded, resolved and current "
                    + "task records; they do not prove semantic correctness or grant permission."),
        ]
    }

    // MARK: Edits (goals.py `edit_criterion`, `add_step`, `edit_step`, `block_step`)

    /// A refusal in Pebble's words.
    struct Refused: Error {
        let words: String
    }

    /// goals.py `_text`: one line, nonempty, under the limit (interaction.py `bounded_text`).
    static func text(_ value: JSONValue?, limit: Int) throws -> String {
        guard let raw = value?.string, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, raw.count <= limit
        else {
            throw Refused(words: "Enter nonempty text under \(limit) characters.")
        }
        guard !raw.contains(where: \.isNewline) else {
            throw Refused(words: "Keep the text on one line without control characters.")
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// goals.py `_ids`.
    static func ids(_ value: JSONValue?, limit: Int) throws -> [String] {
        guard let value, value != .null else { return [] }
        let list = (value.array ?? []).compactMap(\.string)
        guard value.array?.count == list.count, list.count <= limit, Set(list).count == list.count else {
            throw Refused(words: "depends_on must list up to \(limit) unique IDs.")
        }
        return list
    }

    /// goals.py `_graph`: known steps, no step after itself, no loop.
    static func checkGraph(_ steps: [JSONValue]) throws {
        let known = Set(steps.compactMap { $0["id"]?.string })
        var remaining: [String: Set<String>] = [:]
        for step in steps {
            let id = step["id"]?.string ?? ""
            let after = (step["depends_on"]?.array ?? []).compactMap(\.string)
            for dep in after {
                if dep == id { throw Refused(words: "A step cannot depend on itself.") }
                if !known.contains(dep) { throw Refused(words: "Step \(id) depends on an unknown step (\(dep)).") }
            }
            remaining[id] = Set(after)
        }
        while !remaining.isEmpty {
            let ready = remaining.filter { $0.value.isDisjoint(with: remaining.keys) }.map(\.key)
            if ready.isEmpty {
                throw Refused(
                    words: "Step dependencies cannot form a cycle (\(remaining.keys.sorted().joined(separator: ", ")))."
                )
            }
            for id in ready { remaining[id] = nil }
        }
    }

    /// A step's readiness and the goal's derived state, after a change (goals.py `_evaluate`: an active or blocked
    /// goal is blocked exactly while something blocks it).
    static func settle(_ goal: inout [String: JSONValue]) {
        var steps = goal["steps"]?.array ?? []
        let done = Set(steps.filter { $0["status"]?.string == "completed" }.compactMap { $0["id"]?.string })
        for index in steps.indices {
            guard case .object(var step) = steps[index] else { continue }
            let after = Set((step["depends_on"]?.array ?? []).compactMap(\.string))
            step["ready"] = .bool(step["status"]?.string == "pending" && after.isSubset(of: done))
            steps[index] = .object(step)
        }
        goal["steps"] = .array(steps)
        if ["active", "blocked"].contains(goal["state"]?.string ?? "") {
            goal["state"] = (goal["blockers"]?.array ?? []).isEmpty ? "active" : "blocked"
        }
    }

    static func editCriterion(_ goal: inout [String: JSONValue], _ params: JSONValue) throws {
        let text = try text(params["text"], limit: 500)
        var criteria = goal["criteria"]?.array ?? []
        guard let index = criteria.firstIndex(where: { $0["id"] == params["criterion_id"] }),
            case .object(var item) = criteria[index]
        else { throw Refused(words: "Criterion not found in this goal.") }
        if item["status"]?.string == "rejected" {
            throw Refused(words: "This criterion was rejected. Add a new one instead.")
        }
        let key = text.lowercased()
        if criteria.contains(where: {
            $0["id"] != item["id"] && $0["status"]?.string != "rejected" && $0["text"]?.string?.lowercased() == key
        }) {
            throw Refused(words: "This goal already has that criterion.")
        }
        item["text"] = .string(text)
        item["status"] = item["status"]?.string == "candidate" ? "candidate" : "open"
        item["checked_by"] = .null
        item["evidence"] = []
        criteria[index] = .object(item)
        goal["criteria"] = .array(criteria)
    }

    static func addStep(_ goal: inout [String: JSONValue], _ params: JSONValue) throws {
        let title = try text(params["title"], limit: 240)
        let after = try ids(params["depends_on"], limit: 8)
        var steps = goal["steps"]?.array ?? []
        guard steps.count < 20 else { throw Refused(words: "A goal holds up to 20 steps.") }
        let next = (steps.compactMap { $0["id"]?.string.flatMap { Int($0.dropFirst()) } }.max() ?? 0) + 1
        steps.append([
            "id": .string("s\(next)"), "title": .string(title), "status": "pending",
            "depends_on": .array(after.map(JSONValue.string)), "blocker": .null, "ready": false,
        ])
        try checkGraph(steps)
        goal["steps"] = .array(steps)
    }

    static func editStep(_ goal: inout [String: JSONValue], _ params: JSONValue) throws {
        let title = params["title"].flatMap { $0 == .null ? nil : $0 }
        let after = params["depends_on"].flatMap { $0 == .null ? nil : $0 }
        guard title != nil || after != nil else { throw Refused(words: "Change the title, dependencies or criteria.") }
        var steps = goal["steps"]?.array ?? []
        guard let index = steps.firstIndex(where: { $0["id"] == params["step_id"] }),
            case .object(var step) = steps[index]
        else { throw Refused(words: "Step not found in this goal.") }
        if let title {
            let words = try text(title, limit: 240)
            step["title"] = .string(words)
        }
        if let after {
            let chosen = try ids(after, limit: 8)
            step["depends_on"] = .array(chosen.map(JSONValue.string))
        }
        steps[index] = .object(step)
        try checkGraph(steps)
        goal["steps"] = .array(steps)
    }

    static func blockStep(_ goal: inout [String: JSONValue], _ params: JSONValue) throws {
        var reason: String?
        if let given = params["text"], given != .null { reason = try text(given, limit: 300) }
        var steps = goal["steps"]?.array ?? []
        guard let index = steps.firstIndex(where: { $0["id"] == params["step_id"] }),
            case .object(var step) = steps[index],
            let id = step["id"]?.string
        else { throw Refused(words: "Step not found in this goal.") }
        var blockers = goal["blockers"]?.array ?? []
        if let reason {
            if step["status"]?.string == "completed" { throw Refused(words: "This step is completed.") }
            step["status"] = "blocked"
            step["blocker"] = ["kind": "text", "ref": .string(reason), "active": true]
            blockers.removeAll { $0["step_id"]?.string == id && $0["kind"]?.string == "text" }
            blockers.insert(
                [
                    "kind": "text", "ref": .string(id), "label": "Blocked by you", "step_id": .string(id),
                    "detail": .string(reason), "detail_origin": "human",
                ], at: 0)
        } else {
            guard step["status"]?.string == "blocked" else { throw Refused(words: "This step is not blocked.") }
            step["status"] = "pending"
            step["blocker"] = .null
            // The person's note goes; a card the run still waits for stays the goal's, no longer the step's.
            blockers.removeAll { $0["step_id"]?.string == id && $0["kind"]?.string == "text" }
            for position in blockers.indices where blockers[position]["step_id"]?.string == id {
                if case .object(var item) = blockers[position] {
                    item["step_id"] = nil
                    blockers[position] = .object(item)
                }
            }
        }
        steps[index] = .object(step)
        goal["steps"] = .array(steps)
        goal["blockers"] = .array(blockers)
    }

    // MARK: A helper agent in full (agent_manager.py `get`)

    /// The agent's row with what `agent_get` adds: its generation, tools and limits, what it used, and its records.
    static func agentDetail(_ node: JSONValue) -> JSONValue {
        guard case .object(var object) = node else { return node }
        let running = ["queued", "running", "waiting_parent", "waiting_input"].contains(object["status"]?.string ?? "")
        let checker = object["name"]?.string == "Link checker"
        let tools: JSONValue = checker ? ["Read", "WebFetch"] : ["Read", "Grep"]
        let evidence: JSONValue = running ? [] : ["3:call-proof-1"]
        let review: JSONValue = running ? .null : "Parent verification required."
        let records: JSONValue = running ? [["tool": "Read"]] : [["tool": "Read"], ["tool": "Grep"]]
        let messages: JSONValue = running ? [] : [["role": "child", "text": "Done: two fixes."]]
        object["generation"] = 1
        object["tools"] = tools
        object["limits"] = ["max_steps": 8, "max_seconds": 300, "model_tokens": 20000]
        object["write_paths"] = []
        object["dependencies"] = []
        object["evidence_ids"] = evidence
        object["review"] = review
        object["dispatches"] = .int(running ? 2 : 3)
        object["error"] = .null
        object["receipts"] = records  // lint-copy: allow
        object["messages"] = messages
        object["questions"] = []
        object["patches"] = []
        object["effects"] = []
        object["origin"] = "agent"
        object["authorization"] = "none"
        return .object(object)
    }
}

import Foundation

// Lane T (2026-10-31): Details › Task's goal editing and a helper agent's own screen. Pebble's words, word for word,
// from its goal panel and agent panel (read-only Pebble checkout: src/components/GoalPanel.vue, AgentPanel.vue). Where
// the phone must differ (a place that is elsewhere on the phone, an internal word, a control the Mac doesn't have),
// the comment beside the constant says why.
extension AppCopy {
    nonisolated public enum Goals {
        // MARK: Criteria (DT-08)

        public static let edit = "Edit"
        /// The criteria table's column ("Criterion").
        public static let criterion = "Criterion"
        public static func editCriterion(_ id: String) -> String { "Edit criterion \(id)" }
        public static let save = "Save"
        /// Pebble's notice once the criterion's words changed.
        public static func criterionUpdated(_ id: String) -> String {
            "Criterion \(id) updated; its check was cleared."
        }
        /// The phone says before Save what Pebble's notice says after it: a changed criterion is checked again.
        public static let checkClears = "Saving clears its check: it is met again only when it is checked again."

        // MARK: Steps (DT-11, DT-12; goal_step_edit has no button on the Mac)

        public static let noSteps = "No steps yet. Pebble reports progress only on steps you add."
        public static let newStep = "New step"
        public static let stepPlaceholder = "Next piece of work"
        public static let after = "After"
        public static let addStep = "Add step"
        public static let stepAdded = "Step added."
        public static let blockStep = "Block step"
        public static let reason = "Reason"
        public static let reasonPlaceholder = "What is in the way?"
        public static func stepBlocked(_ id: String) -> String { "Step \(id) blocked." }
        public static let unblock = "Unblock"
        public static func unblockStep(_ id: String) -> String { "Unblock step \(id)" }
        public static func stepUnblocked(_ id: String) -> String { "Step \(id) unblocked." }
        /// The phone's own: Pebble's window has no button for `goal_step_edit`, so its words follow "Edit criterion".
        public static let editStep = "Edit step"
        public static func editStepNamed(_ id: String) -> String { "Edit step \(id)" }
        public static func stepUpdated(_ id: String) -> String { "Step \(id) updated." }
        /// A step's menu, for VoiceOver: the step's id and title.
        public static func stepActions(_ id: String, _ title: String) -> String { "\(id) \u{00B7} \(title)" }
        /// "s1 · Add the toggle" (Pebble's Block step choices).
        public static func stepChoice(_ id: String, _ title: String) -> String { "\(id) \u{00B7} \(title)" }
        /// "After s1, s2" (the steps table's After column).
        public static func afterSteps(_ ids: [String]) -> String? {
            ids.isEmpty ? nil : "\(after) \(ids.joined(separator: ", "))"
        }
        /// The steps table's Blocker column (GoalPanel.vue `blockerText`).
        public static func stepBlocker(kind: String?, ref: String?, active: Bool, ready: Bool) -> String? {
            guard let kind else { return ready ? "ready" : nil }
            let base = blockerKind(kind) + (active ? "" : " (resolved)")
            if kind == "text", let ref, !ref.isEmpty { return "\(base): \(ref)" }
            return base
        }
        /// Pebble's limit on a step's title, said when the field is full (goals.py `TITLE`).
        public static func atLimit(_ characters: Int) -> String { "Pebble keeps up to \(characters) characters here." }
        /// Pebble refuses more than 20 steps (goals.py `MAX_STEPS`): "A goal holds up to 20 steps."
        public static func stepsFull(_ limit: Int) -> String { "A goal holds up to \(limit) steps." }

        // MARK: Blockers (DT-13)

        /// Pebble captions its table "Blockers (host records)"; the phone says "Blockers" (its word for Pebble's own
        /// records never shows on screen).
        public static let blockers = "Blockers"
        /// GoalPanel.vue `blockerKinds`.
        public static func blockerKind(_ kind: String) -> String {
            switch kind {
            case "question": "Question"
            case "approval": "Review"
            case "failure": "Failure"
            case "text": "Your note"
            default: "unknown"
            }
        }
        /// The Blockers table's Next column. "Review" opens the waiting card; the Mac's "task panel" is Details ›
        /// Activity on the phone, and a question waits in the conversation and on Reviews.
        public static let review = "Review"
        public static let reviewHint = "Opens the card that waits for your review"
        public static let answerInConversation = "Answer it in the conversation or on Reviews."
        public static let inspectInActivity = "Inspect it in Details \u{203A} Activity."
        public static func blockerStep(_ id: String) -> String { "step \(id)" }
        /// Pebble marks words a model wrote "agent-authored"; the phone says so in plain words.
        public static let writtenByPebble = "Written by Pebble"
        /// The card Review opened was decided meanwhile (it no longer waits on this iPhone).
        public static let reviewGone = "Nothing waits for this review now."

        // MARK: A helper agent (DT-21, AgentPanel.vue)

        public static let loadingAgent = "Loading agent details\u{2026}"
        public static let technicalDetails = "Technical details"
        public static let task = "Task"
        public static let status = "Status"
        public static let opensAgentHint = "Opens the agent\u{2019}s task, result and use"
        /// AgentPanel.vue `status`: a state Pebble knows, in words; anything else "unknown".
        public static func agentStatus(_ status: String) -> String {
            let known = [
                "queued", "running", "waiting_parent", "waiting_input", "interrupted", "completed", "failed", "stopped",
                "budget_exhausted",
            ]
            return known.contains(status) ? status.replacingOccurrences(of: "_", with: " ") : "unknown"
        }
        /// "Used 3 model calls, 4,180 tokens, 21 s" (AgentPanel.vue `usageText`), or nil with nothing to say.
        public static func used(calls: Int?, tokens: Int?, seconds: Double?) -> String? {
            let parts = [
                calls.map { "\($0) \($0 == 1 ? "model call" : "model calls")" },
                tokens.map { "\(AppCopy.Details.grouped($0)) tokens" },
                seconds.flatMap { $0.isFinite ? "\(Int($0.rounded())) s" : nil },
            ].compactMap { $0 }
            return parts.isEmpty ? nil : "Used " + parts.joined(separator: ", ")
        }
        /// A tree row's line (AgentPanel.vue `rowLine`): the task, cut at 120 characters, then the use.
        public static func rowLine(task: String, used: String?) -> String? {
            let flat = task.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let cut = flat.count > 120 ? String(flat.prefix(119)) + "\u{2026}" : flat
            let parts = [cut.isEmpty ? nil : cut, used].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
        }
        /// "Agent: a-1 · Parent: a-0". Pebble also names "Task: {id}", which is the agent's own id again
        /// (agent_tree.py `_public` sets `agent_id` to `id`), so the phone says it once.
        public static func identity(agent: String, parent: String?) -> String {
            "Agent: \(agent)" + (parent.map { " \u{00B7} Parent: \($0)" } ?? "")
        }
        /// "Generation 2 · Tools: Read, Grep · Review: …" (the tree's technical line).
        public static func generationLine(_ generation: Int?, tools: [String], review: String?) -> String {
            "Generation \(generation ?? 1) \u{00B7} Tools: \(tools.isEmpty ? "none" : tools.joined(separator: ", "))"
                + (review.map { " \u{00B7} Review: \($0)" } ?? "")
        }
        public static let agentLimits = "Agent limits"
        /// "Dispatches: 3 · Charged tokens: 4180 · Model seconds: 21.4" (AgentPanel.vue `accounting`).
        public static func accounting(dispatches: Int?, tokens: Int?, seconds: Double?) -> String? {
            let parts = [
                dispatches.map { "Dispatches: \($0)" }, tokens.map { "Charged tokens: \($0)" },
                seconds.flatMap { $0.isFinite ? "Model seconds: \(number($0))" : nil },
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
        }
        public static func writePaths(_ paths: [String]) -> String { "Write paths: " + paths.joined(separator: ", ") }
        public static func dependencies(_ ids: [String]) -> String { "Dependencies: " + ids.joined(separator: ", ") }
        public static func evidence(_ ids: [String]) -> String { "Evidence: " + ids.joined(separator: ", ") }
        public static let resultRecord = "Result record"
        /// AgentPanel.vue `collections`, with their counts: "Messages (2)".
        public static func records(_ key: String, count: Int) -> String {
            let title =
                switch key {
                case "messages": "Messages"
                case "questions": "Questions"
                case "patches": "Patches"
                case "effects": "Execution requests"
                default: "Tool records"
                }
            return "\(title) (\(count))"
        }
        public static func fact(_ name: String, _ value: String) -> String { "\(name): \(value)" }

        /// 21.4 as Pebble writes a number (no trailing zeros).
        static func number(_ value: Double) -> String {
            value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        }
    }
}

import Foundation
import PebbleProtocol

// Lane T (2026-10-31): editing a goal from Details › Task, as Pebble's goal panel does (GoalPanel.vue `saveEdit`,
// `addStep`, `block`, `unblock`; goals.py `methods`). Every change names the revision the person saw, and Pebble
// answers with the goal as it is now, or refuses a stale revision, a loop between steps or a closed goal in its own
// words. None of these settles a goal, so none asks for Face ID unless the bridge lists it (`act`).
//
// The blockers come with `goal_get` (goals.py `blockers()` answers `get()`'s own list), so the phone reads them there:
// `goal_blockers` isn't one of the bridge's reads, and each call would be recorded on the Mac as "changed a goal".

extension RemoteStore {
    /// A criterion's Edit › Save (`goal_criterion_edit`): Pebble clears its check, so it must be checked again.
    public func editCriterion(_ criterion: GoalCriterion, to text: String, of goal: GoalRecord) async throws
        -> GoalRecord
    {
        try await changeGoal(
            "goal_criterion_edit", goal, ["criterion_id": .string(criterion.id), "text": .string(text)],
            reason: GoalWords.editCriterionReason)
    }

    /// Steps › Add step (`goal_step_add`), after the steps the person chose.
    public func addStep(_ title: String, after: [String], to goal: GoalRecord) async throws -> GoalRecord {
        try await changeGoal(
            "goal_step_add", goal, ["title": .string(title), "depends_on": .array(after.map(JSONValue.string))],
            reason: GoalWords.addStepReason)
    }

    /// A step's Edit (`goal_step_edit`): only what changed is sent (Pebble keeps the rest, and its criteria).
    public func editStep(
        _ step: GoalRecord.Step, title: String?, after: [String]?, of goal: GoalRecord
    ) async throws -> GoalRecord {
        var params: [String: JSONValue] = ["step_id": .string(step.id)]
        if let title { params["title"] = .string(title) }
        if let after { params["depends_on"] = .array(after.map(JSONValue.string)) }
        return try await changeGoal("goal_step_edit", goal, params, reason: GoalWords.editStepReason)
    }

    /// Block step, with the person's reason (`goal_step_block` with `text`).
    public func blockStep(_ step: GoalRecord.Step, reason: String, of goal: GoalRecord) async throws -> GoalRecord {
        try await changeGoal(
            "goal_step_block", goal, ["step_id": .string(step.id), "text": .string(reason)],
            reason: GoalWords.blockStepReason)
    }

    /// Unblock (`goal_step_block` without `text`): the step returns to pending, whatever blocked it.
    public func unblockStep(_ step: GoalRecord.Step, of goal: GoalRecord) async throws -> GoalRecord {
        try await changeGoal(
            "goal_step_block", goal, ["step_id": .string(step.id)], reason: GoalWords.unblockStepReason)
    }

    /// The card a review blocker names, when it waits on this phone.
    public func waitingReview(for blocker: GoalBlocker, in chat: ChatID) -> ReviewItem? {
        guard blocker.waitsForReview else { return nil }
        for item in waiting {
            if case .review(let review) = item, review.chatID == chat, review.actionID == blocker.ref { return review }
        }
        return nil
    }

    private func changeGoal(
        _ method: String, _ goal: GoalRecord, _ more: [String: JSONValue], reason: String
    ) async throws -> GoalRecord {
        var params: [String: JSONValue] = [
            "chat_id": .string(goal.chatID), "goal_id": .string(goal.id), "revision": .int(goal.revision),
        ]
        params.merge(more) { _, new in new }
        let answer = try await act(method, .object(params), reason: reason)
        guard let changed = GoalRecord(json: answer, chatID: goal.chatID), changed.id == goal.id else {
            throw report(unreadable())
        }
        return changed
    }
}

/// What Face ID says, should the bridge ever ask for it on a goal's edit (Kit can't read PebbleDesign's copy).
public enum GoalWords {
    public static let editCriterionReason = "Edit a criterion of your goal"
    public static let addStepReason = "Add a step to your goal"
    public static let editStepReason = "Edit a step of your goal"
    public static let blockStepReason = "Block a step of your goal"
    public static let unblockStepReason = "Unblock a step of your goal"
}

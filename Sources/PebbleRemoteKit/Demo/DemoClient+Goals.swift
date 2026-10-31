import Foundation
import PebbleProtocol

// Lane T (2026-10-31): the demo answers goal edits and `agent_get` as Pebble does (goals.py `_mutate` and its human
// routes; agent_manager.py `get`), refusals word for word, and the views' history, Stop and exports
// (DemoClient+Exports).

extension DemoClient {
    /// Lane T's methods; nil for any other.
    func laneTAnswer(_ method: String, _ params: JSONValue) throws -> JSONValue? {
        switch method {
        case "goal_criterion_edit", "goal_step_add", "goal_step_edit", "goal_step_block":
            return try editGoal(method, params)
        case "agent_get":
            let run = params["run_id"]?.string ?? ""
            guard runs[run] != nil else { throw refusal("Root run not found in this conversation.") }
            guard let node = details.agents[run]?.first(where: { $0["id"] == params["agent_id"] }) else {
                throw refusal("Agent not found in this root tree.")
            }
            return DemoGoals.agentDetail(node)
        default:
            return try viewsAndExportsAnswer(method, params)
        }
    }

    /// goals.py `_mutate`: the revision the person saw, then a goal still open, then the change; the goal comes back
    /// as it is now, one revision on.
    private func editGoal(_ method: String, _ params: JSONValue) throws -> JSONValue {
        guard let chat = params["chat_id"]?.string, chatIndex(chat) != nil else {
            throw refusal("Conversation not found.")
        }
        guard let index = details.goals[chat]?.firstIndex(where: { $0["id"] == params["goal_id"] }),
            case .object(var goal)? = details.goals[chat]?[index]
        else { throw refusal("Goal not found in this conversation.") }
        let revision = goal["revision"]?.int ?? 0
        guard params["revision"]?.int == revision else {
            throw refusal("This goal changed (revision \(revision)). Refresh it before editing.")
        }
        let state = goal["state"]?.string ?? ""
        if ["done", "abandoned"].contains(state) { throw refusal("This goal is \(state); its record is closed.") }
        do {
            switch method {
            case "goal_criterion_edit": try DemoGoals.editCriterion(&goal, params)
            case "goal_step_add": try DemoGoals.addStep(&goal, params)
            case "goal_step_edit": try DemoGoals.editStep(&goal, params)
            default: try DemoGoals.blockStep(&goal, params)
            }
        } catch let refused as DemoGoals.Refused {
            throw refusal(refused.words)
        }
        DemoGoals.settle(&goal)
        goal["revision"] = .int(revision + 1)
        goal["updated"] = .double(now().timeIntervalSince1970)
        details.goals[chat]?[index] = .object(goal)
        emit(
            "goal",
            [
                "chat_id": .string(chat), "goal_id": goal["id"] ?? .null, "revision": .int(revision + 1),
                "state": goal["state"] ?? .null,
            ])
        return DemoDetails.snapshot(.object(goal))
    }
}

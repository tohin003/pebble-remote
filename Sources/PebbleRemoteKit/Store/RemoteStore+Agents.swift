import Foundation
import PebbleProtocol

// Lane T (2026-10-31): choosing a helper agent in Details › Task reads it (AgentPanel.vue `loadDetail`; app.py
// `agent_get(chat_id, run_id, agent_id)`). The bridge doesn't list it among the reads that need no unlock, so it is
// made when the person chooses the agent, not on a timer.

extension RemoteStore {
    /// One agent in full. Pebble checks it belongs to this task; an answer about another agent is refused here too.
    public func agentDetail(_ agent: AgentNode, in chat: ChatID) async throws -> AgentDetail {
        let params: JSONValue = [
            "chat_id": .string(chat), "run_id": .string(agent.runID), "agent_id": .string(agent.id),
        ]
        let result = try await answer("agent_get", params)
        guard let detail = AgentDetail(json: result, runID: agent.runID), detail.node.id == agent.id,
            detail.node.runID == agent.runID
        else { throw report(unreadable()) }
        return detail
    }
}

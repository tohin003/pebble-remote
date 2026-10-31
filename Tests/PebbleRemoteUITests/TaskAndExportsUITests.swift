import Foundation
import PebbleProtocol
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane T: what the agent's screen folds under Technical details, and which views answer only in their current
/// revision.
@MainActor
struct TaskAndExportsUITests {
    @Test func anAgentsTechnicalDetailsAreAgentPanelsLinesInItsOrder() {
        let node = AgentNode(
            id: "a1", runID: "r1", parentID: "a0", name: "Helper", task: "Look", status: "completed", tokens: 4180,
            seconds: 21.4)
        let detail = AgentDetail(
            node: node, generation: 2, tools: ["Read"], limits: [.init(name: "max steps", value: "8")],
            writePaths: ["docs/"],
            evidence: ["2:call"], dispatches: 3,
            resultFacts: [.init(name: "checks", value: "Parent verification required.")],
            records: [.init(key: "messages", count: 2)])
        #expect(
            AgentScreen.technicalLines(detail) == [
                "Agent: a1 \u{00B7} Parent: a0", "Generation 2 \u{00B7} Tools: Read", "Agent limits: max steps: 8",
                "Dispatches: 3 \u{00B7} Charged tokens: 4180 \u{00B7} Model seconds: 21.4", "Write paths: docs/",
                "Result record: checks: Parent verification required.", "Evidence: 2:call", "Messages (2)",
            ])
        let bare = AgentDetail(node: AgentNode(id: "a2", runID: "r1", task: "", status: "running"))
        #expect(AgentScreen.technicalLines(bare) == ["Agent: a2", "Generation 1 \u{00B7} Tools: none"])
    }

    @Test func formsAndQuizzesAnswerOnlyInTheirCurrentRevision() {
        #expect(ViewScreen.answersOnlyWhenCurrent("form") && ViewScreen.answersOnlyWhenCurrent("quiz"))
        #expect(!ViewScreen.answersOnlyWhenCurrent("table") && !ViewScreen.answersOnlyWhenCurrent("dashboard"))
    }

    @Test func eachGoalEditHasItsOwnSheet() {
        let step = GoalRecord.Step(id: "s1", title: "Write it", status: "pending")
        let edits: [GoalEdit] = [
            .criterion(GoalCriterion(id: "c1", text: "Tests pass")), .addStep, .step(step), .block(step),
        ]
        #expect(Set(edits.map(\.id)).count == 4)
    }
}

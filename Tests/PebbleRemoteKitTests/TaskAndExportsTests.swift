import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// Lane T: goal editing, an agent in full, a view's history and Stop, and exports send what Pebble's own window sends
// (read-only Pebble checkout: goals.py `methods`, app.py's dispatcher, GoalPanel.vue, AgentPanel.vue,
// ArtifactPanel.vue, ExportPanel.vue), read Pebble's answers without trusting them, ask for Face ID only where the
// bridge says, and work in the demo.

/// The methods lane T's controls call.
private let laneTMethods: Set<String> = [
    "goal_criterion_edit", "goal_step_add", "goal_step_edit", "goal_step_block", "agent_get", "artifact_history",
    "artifact_stop", "export_preview", "export_render", "export_cancel", "export_discard", "export_list", "export_get",
]

private let goalJSON: JSONValue = [
    "id": "g1", "chat_id": "c1", "title": "Ship it", "revision": 5, "state": "blocked",
    "criteria": [
        [
            "id": "c1", "text": "Tests pass", "kind": "evidence", "status": "met", "origin": "human",
            "checked_by": "host",
        ]
    ],
    "steps": [
        ["id": "s1", "title": "Write it", "status": "completed", "depends_on": [], "blocker": .null, "ready": false],
        [
            "id": "s2", "title": "Ship it", "status": "blocked", "depends_on": ["s1", 7],
            "blocker": ["kind": "text", "ref": "Waiting for design", "active": true], "ready": false,
        ],
        [
            "id": "s3", "title": "Tell people", "status": "pending", "depends_on": ["s1"],
            "blocker": ["ref": "no kind"], "ready": true,
        ],
    ],
    "blockers": [
        [
            "kind": "text", "ref": "s2", "label": "Blocked by you", "step_id": "s2", "detail": "Waiting for design",
            "detail_origin": "human",
        ],
        ["kind": "approval", "ref": "a9", "label": "Needs your review", "run_id": "r1"],
        ["label": "no kind"],
    ],
    "progress": ["criteria_met": 1, "criteria_total": 1, "steps_completed": 1, "steps_total": 3],
]

private let tableView: JSONValue = [
    "id": "v1", "chat_id": "c1", "kind": "table", "title": "Numbers", "revision": 2, "status": "ready",
    "data": ["columns": [["id": "a", "label": "A"]], "rows": [["a": 1]]],
]

@MainActor
private func demoStore(pace: Double = 0, sleeper: DemoClient.Sleeper? = nil) async -> RemoteStore {
    let client = DemoClient(pace: pace, autoplay: false, now: { Fixture.t0 }, sleeper: sleeper)
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.clock = { Fixture.t0 }
    store.start()
    _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
    return store
}

@MainActor
struct TaskAndExportsTests {
    // MARK: - Goal editing (DT-08, DT-11, DT-12, DT-13)

    @Test func aGoalReadsItsStepsAfterBlockersAndReadinessAsPebbleSendsThem() throws {
        let goal = try #require(GoalRecord(json: goalJSON, chatID: "c1"))
        #expect(goal.steps.map(\.after) == [[], ["s1"], ["s1"]], "a step id that isn't text is left out")
        #expect(goal.steps[1].blocker == StepBlocker(kind: "text", ref: "Waiting for design", isActive: true))
        #expect(goal.steps[1].isBlocked && goal.steps[2].isReady && goal.steps[2].blocker == nil)
        #expect(
            goal.blockers == ["Blocked by you", "Needs your review", "no kind"], "lane Y's labels stay as they were")
        #expect(goal.blockerItems.map(\.kind) == ["text", "approval"], "a blocker without its kind is left out")
        #expect(goal.blockerItems[0].stepID == "s2" && goal.blockerItems[0].detailOrigin == "human")
        #expect(goal.blockerItems[1].waitsForReview && goal.blockerItems[1].runID == "r1")
        #expect(goal.blockableSteps.map(\.id) == ["s3"])
        #expect(goal.possibleAfter(for: goal.steps[2]).map(\.id) == ["s1", "s2"])
    }

    @Test func editingAGoalSendsPebblesParamsWithTheRevisionSeenAndNoFaceID() async throws {
        let fake = FakeClient { _, _ in goalJSON }
        let store = RemoteStore(client: fake)
        let goal = try #require(GoalRecord(json: goalJSON, chatID: "c1"))
        let base: [String: JSONValue] = ["chat_id": "c1", "goal_id": "g1", "revision": 5]
        func with(_ more: [String: JSONValue]) -> JSONValue { .object(base.merging(more) { $1 }) }

        _ = try await store.editCriterion(goal.criteria[0], to: "Tests pass on main", of: goal)
        _ = try await store.addStep("Write the notes", after: ["s1", "s3"], to: goal)
        _ = try await store.editStep(goal.steps[2], title: "Tell everyone", after: nil, of: goal)
        _ = try await store.editStep(goal.steps[2], title: nil, after: [], of: goal)
        _ = try await store.blockStep(goal.steps[2], reason: "Waiting for the release", of: goal)
        _ = try await store.unblockStep(goal.steps[1], of: goal)

        #expect(
            fake.calls("goal_criterion_edit").map(\.params) == [
                with(["criterion_id": "c1", "text": "Tests pass on main"])
            ])
        #expect(
            fake.calls("goal_step_add").map(\.params) == [
                with(["title": "Write the notes", "depends_on": ["s1", "s3"]])
            ])
        #expect(
            fake.calls("goal_step_edit").map(\.params) == [
                with(["step_id": "s3", "title": "Tell everyone"]), with(["step_id": "s3", "depends_on": []]),
            ], "only what changed is sent")
        #expect(
            fake.calls("goal_step_block").map(\.params) == [
                with(["step_id": "s3", "text": "Waiting for the release"]), with(["step_id": "s2"]),
            ], "Unblock sends no text")
        #expect(fake.calls.allSatisfy { !$0.elevated })
    }

    @Test func anAnswerAboutAnotherGoalIsRefusedAsUnreadable() async throws {
        let other: JSONValue = ["id": "g2", "chat_id": "c1", "title": "Other", "revision": 1, "state": "active"]
        let fake = FakeClient { _, _ in other }
        let store = RemoteStore(client: fake)
        let goal = try #require(GoalRecord(json: goalJSON, chatID: "c1"))
        await #expect(throws: RemoteCallError.self) { _ = try await store.addStep("x", after: [], to: goal) }
        #expect(store.notice?.message == StoreWords.unreadableAnswer)
    }

    @Test func theDemosGoalIsEditedAsPebbleChecksIt() async throws {
        let store = await demoStore()
        let current = try #require(try await store.goals(in: DemoData.themeChat).first(where: \.isCurrent))
        var goal = try await store.goal(current.id, in: DemoData.themeChat)
        #expect(goal.steps.map(\.id) == ["s1", "s2", "s3"] && goal.blockerItems.map(\.kind) == ["text", "failure"])

        goal = try await store.editCriterion(goal.criteria[0], to: "The toggle follows the system", of: goal)
        #expect(goal.criteria[0].status == "open" && goal.criteria[0].checkedBy == nil, "its check was cleared")

        let stale = goal
        goal = try await store.addStep("Write the release note", after: ["s1"], to: goal)
        #expect(goal.steps.last?.id == "s4" && goal.steps.last?.after == ["s1"] && goal.steps.last?.isReady == true)
        await #expect(throws: RemoteCallError.self) { _ = try await store.addStep("Again", after: [], to: stale) }
        #expect(store.notice?.message == "This goal changed (revision \(goal.revision)). Refresh it before editing.")

        await #expect(throws: RemoteCallError.self) {
            _ = try await store.editStep(goal.steps[0], title: nil, after: ["s2"], of: goal)
        }
        #expect(store.notice?.message.hasPrefix("Step dependencies cannot form a cycle (") == true)

        goal = try await store.editStep(goal.steps[3], title: "Write the release notes", after: nil, of: goal)
        #expect(goal.steps[3].title == "Write the release notes" && goal.steps[3].after == ["s1"])

        goal = try await store.blockStep(goal.steps[1], reason: "Waiting for CI", of: goal)
        #expect(goal.steps[1].isBlocked && goal.steps[1].blocker?.ref == "Waiting for CI" && goal.state == "blocked")
        #expect(goal.blockerItems.first?.stepID == "s2" && goal.blockerItems.first?.detail == "Waiting for CI")

        goal = try await store.unblockStep(goal.steps[2], of: goal)
        goal = try await store.unblockStep(goal.steps[1], of: goal)
        #expect(goal.steps[1].status == "pending" && goal.steps[2].status == "pending")
        #expect(
            goal.blockerItems.map(\.kind) == ["failure"] && goal.state == "blocked", "the held task still blocks it")
        await #expect(throws: RemoteCallError.self) { _ = try await store.unblockStep(goal.steps[1], of: goal) }
        #expect(store.notice?.message == "This step is not blocked.")
    }

    @Test func theDemosReviewBlockerOpensTheWaitingNpmTestCard() async throws {
        let store = await demoStore()
        let current = try #require(try await store.goals(in: DemoData.readmeChat).first(where: \.isCurrent))
        let goal = try await store.goal(current.id, in: DemoData.readmeChat)
        let blocker = try #require(goal.blockerItems.first)
        #expect(blocker.waitsForReview && blocker.stepID == "s2")
        _ = await eventually { store.waitingReview(for: blocker, in: DemoData.readmeChat) != nil }
        #expect(store.waitingReview(for: blocker, in: DemoData.readmeChat)?.actionID == DemoData.readmeCard)
        #expect(store.waitingReview(for: blocker, in: DemoData.themeChat) == nil, "only this conversation's card")
    }

    // MARK: - An agent in full (DT-21)

    @Test func anAgentIsReadByItsTaskAndItsTechnicalDetailsAreKept() async throws {
        let detailJSON: JSONValue = [
            "id": "a1", "agent_id": "a1", "run_id": "r1", "parent_id": "a0", "generation": 2, "name": "Helper",
            "task": "Look", "status": "completed", "tools": ["Read", 3],
            "limits": ["max_steps": 8, "nested": ["x": 1]],
            "write_paths": ["docs/"], "dependencies": [], "evidence_ids": ["2:call"], "review": "", "dispatches": 3,
            "charged_tokens": 4180, "elapsed": 21.4, "error": "",
            "result": ["text": "Two fixes.", "checks": "Parent verification required."],
            "receipts": [[:], [:]], "messages": [], "questions": [[:]],  // lint-copy: allow
        ]
        let fake = FakeClient { _, _ in detailJSON }
        let store = RemoteStore(client: fake)
        let node = AgentNode(id: "a1", runID: "r1", task: "Look", status: "completed")
        let detail = try await store.agentDetail(node, in: "c1")
        #expect(fake.calls("agent_get").map(\.params) == [["chat_id": "c1", "run_id": "r1", "agent_id": "a1"]])
        #expect(fake.calls.allSatisfy { !$0.elevated })
        #expect(detail.node.result == "Two fixes." && detail.node.tokens == 4180 && detail.node.parentID == "a0")
        #expect(detail.tools == ["Read"] && detail.limits == [.init(name: "max steps", value: "8")])
        #expect(detail.resultFacts == [.init(name: "checks", value: "Parent verification required.")])
        #expect(detail.records.map(\.key) == ["receipts", "questions"])  // lint-copy: allow
        #expect(detail.review == nil && detail.error == nil && detail.dispatches == 3 && detail.generation == 2)

        let stranger = FakeClient { _, _ in ["agent_id": "a2", "run_id": "r1", "status": "running"] }
        await #expect(throws: RemoteCallError.self) {
            _ = try await RemoteStore(client: stranger).agentDetail(node, in: "c1")
        }
    }

    @Test func theDemosAgentsAreReadInFull() async throws {
        let store = await demoStore()
        let agents = try await store.agents(in: DemoData.readmeChat, run: DemoData.readmeRun)
        let proofreader = try #require(agents.first { $0.name == "Proofreader" })
        let detail = try await store.agentDetail(proofreader, in: DemoData.readmeChat)
        #expect(detail.node.result?.hasPrefix("Two fixes") == true && detail.resultFacts.map(\.name) == ["checks"])
        #expect(detail.dispatches == 3 && !detail.records.isEmpty && detail.review != nil)
        let gone = AgentNode(id: "a-gone", runID: DemoData.readmeRun, task: "", status: "running")
        await #expect(throws: RemoteCallError.self) { _ = try await store.agentDetail(gone, in: DemoData.readmeChat) }
        #expect(store.notice?.message == "Agent not found in this root tree.")
    }

    // MARK: - A view's history and Stop (CV-02, CV-08, CV-09)

    @Test func aViewsRevisionsAreReadWithoutReplacingTheCurrentOne() async throws {
        let first: JSONValue = [
            "id": "v1", "chat_id": "c1", "kind": "table", "title": "Numbers", "revision": 1, "status": "ready",
            "data": ["columns": [["id": "a", "label": "A"]], "rows": []],
        ]
        let fake = FakeClient { method, params in
            switch method {
            case "artifact_history": return [tableView, first]
            case "artifact_get": return params["revision"] == 1 ? first : tableView
            default: return .bool(true)
            }
        }
        let store = RemoteStore(client: fake)
        let view = try #require(PebbleArtifact(json: tableView))
        let history = try await store.viewHistory(view)
        #expect(history.map(\.revision) == [1, 2], "oldest first")
        let earlier = try await store.readRevision(1, of: view)
        #expect(earlier.revision == 1 && store.views(in: "c1").isEmpty, "an earlier revision is never remembered")
        #expect(fake.calls("artifact_history").map(\.params) == [["chat_id": "c1", "id": "v1"]])
        #expect(fake.calls("artifact_get").map(\.params) == [["chat_id": "c1", "id": "v1", "revision": 1]])

        let mixed = FakeClient { _, _ in [tableView, ["id": "v9", "chat_id": "c1", "kind": "table", "revision": 1]] }
        await #expect(throws: RemoteCallError.self) { _ = try await RemoteStore(client: mixed).viewHistory(view) }
    }

    @Test func stoppingAViewSendsTheRevisionSeenAndKeepsTheStoppedCopy() async throws {
        var stoppedJSON = tableView.object ?? [:]
        stoppedJSON["revision"] = 3
        stoppedJSON["status"] = "stopped"
        let answer = JSONValue.object(stoppedJSON)
        let fake = FakeClient { _, _ in answer }
        let store = RemoteStore(client: fake)
        let view = try #require(PebbleArtifact(json: tableView))
        let stopped = try await store.stopView(view)
        #expect(stopped.status == .stopped && !stopped.isLive && stopped.revision == 3)
        #expect(fake.calls("artifact_stop").map(\.params) == [["chat_id": "c1", "id": "v1", "revision": 2]])
        #expect(fake.calls("artifact_stop").first?.elevated == false)
        #expect(store.views(in: "c1").first?.status == .stopped)
    }

    @Test func theDemosTableHasAnEarlierRevisionAndStopsOnce() async throws {
        let store = await demoStore()
        let table = try await store.readView("v-commits-table", in: DemoData.commitsChat)
        #expect(table.revision == 2)
        let history = try await store.viewHistory(table)
        #expect(history.map(\.revision) == [1, 2])
        let earlier = try await store.readRevision(1, of: table)
        guard case .table(let before) = earlier.view, case .table(let after) = table.view else {
            Issue.record("both revisions are tables")
            return
        }
        #expect(before.rows.count + 1 == after.rows.count, "revision 1 had one author fewer")
        let stopped = try await store.stopView(table)
        #expect(stopped.status == .stopped && stopped.revision == 3)
        #expect(try await store.viewHistory(stopped).map(\.revision) == [1, 2, 3])
        await #expect(throws: RemoteCallError.self) { _ = try await store.stopView(table) }
        #expect(store.notice?.message == "This artifact revision is stale. Refresh before stopping.")
        #expect(try await store.stopView(stopped).revision == 3, "a stopped view comes back as it is")
    }

    // MARK: - Exports (DT-26 to DT-31)

    @Test func anExportSendsPebblesParamsAndNeverFaceID() async throws {
        let receipt: JSONValue = [
            "export_id": "x1", "format": "html", "status": "verified", "title": "Numbers",
            "source": ["kind": "artifact", "id": "v1", "revision": 2],
            "file": ["suggested_name": "Numbers.html", "bytes": 2048, "sha256": "abcdef0123456789"],
            "checks": [
                ["name": "parsed", "label": "The file opens and parses", "passed": true, "detail": "Parsed."],
                ["passed": true],
            ],
            "readback": ["text_coverage": 0.9987], "notes": ["A note."], "created": 1_761_900_000.5,
            "saves": [
                ["id": "s1", "state": "saved", "path": "/Users/you/Numbers.html", "sha256": "abc", "verified": true]
            ],
        ]
        let fake = FakeClient { method, _ in
            switch method {
            case "export_preview":
                return [
                    "plan_id": "p1", "format": "html", "source": ["revision": 2], "pages_estimate": 1,
                    "deadline": 1_761_900_600,
                ]
            case "export_render", "export_get": return receipt
            case "export_list": return [receipt, ["format": "csv"]]
            case "export_cancel": return true
            default: return ["export_id": "x1", "status": "discarded"]
            }
        }
        let store = RemoteStore(client: fake)
        let view = try #require(PebbleArtifact(json: tableView))
        var quizJSON = tableView.object ?? [:]
        quizJSON["kind"] = "quiz"
        let quiz = try #require(PebbleArtifact(json: .object(quizJSON)))

        let plan = try await store.previewExport(of: view, as: .html, includeAnswers: true)
        _ = try await store.previewExport(of: quiz, as: .docx, includeAnswers: true)
        #expect(plan.id == "p1" && plan.revision == 2 && plan.pages == 1 && plan.deadline != nil)
        #expect(
            fake.calls("export_preview").map(\.params) == [
                [
                    "chat_id": "c1", "source": ["kind": "artifact", "id": "v1", "revision": 2], "format": "html",
                    "options": [:],
                ],
                [
                    "chat_id": "c1", "source": ["kind": "artifact", "id": "v1", "revision": 2], "format": "docx",
                    "options": ["include_answers": true],
                ],
            ], "the answer key's choice goes only with a quiz")

        let made = try await store.renderExport(plan, in: "c1")
        #expect(try await store.cancelExport(plan, in: "c1"))
        try await store.discardExport("x1", in: "c1")
        let list = try await store.exports(in: "c1")
        let full = try await store.export("x1", in: "c1")
        #expect(fake.calls("export_render").map(\.params) == [["chat_id": "c1", "plan_id": "p1"]])
        #expect(fake.calls("export_cancel").map(\.params) == [["chat_id": "c1", "plan_id": "p1"]])
        #expect(fake.calls("export_discard").map(\.params) == [["chat_id": "c1", "export_id": "x1"]])
        #expect(fake.calls("export_list").map(\.params) == [["chat_id": "c1"]])
        #expect(fake.calls("export_get").map(\.params) == [["chat_id": "c1", "export_id": "x1"]])
        #expect(fake.calls.allSatisfy { !$0.elevated })

        #expect(
            made.status == "verified" && made.keepsFile && made.checks.count == 1,
            "a check without its name is left out")
        #expect(
            made.coverage == 0.9987 && made.suggestedName == "Numbers.html" && made.revision == 2
                && made.notes == ["A note."])
        #expect(list.count == 1, "a record without its id is left out")
        #expect(
            full.saves == [
                ExportSave(id: "s1", state: "saved", path: "/Users/you/Numbers.html", sha256: "abc", verified: true)
            ])
    }

    @Test func theDemoPreviewsMakesListsAndDeletesAnExportAsPebbleDoes() async throws {
        let store = await demoStore()
        let chart = try await store.readView("v-commits-chart", in: DemoData.commitsChat)
        await #expect(throws: RemoteCallError.self) {
            _ = try await store.previewExport(of: chart, as: .csv, includeAnswers: false)
        }
        #expect(store.notice?.message == "CSV holds exactly one table; this source has 0. Use XLSX instead.")

        let table = try await store.readView("v-commits-table", in: DemoData.commitsChat)
        let plan = try await store.previewExport(of: table, as: .html, includeAnswers: false)
        let made = try await store.renderExport(plan, in: DemoData.commitsChat)
        #expect(
            made.status == "verified" && made.keepsFile && made.checks.allSatisfy(\.passed) && made.checks.count == 7)
        await #expect(throws: RemoteCallError.self) { _ = try await store.renderExport(plan, in: DemoData.commitsChat) }
        #expect(store.notice?.message == "This export preview is no longer available. Preview it again.")

        let word = try await store.renderExport(
            try await store.previewExport(of: table, as: .docx, includeAnswers: false), in: DemoData.commitsChat)
        #expect(word.status == "unverified" && word.failedChecks == ["thumbnail"])

        let list = try await store.exports(in: DemoData.commitsChat)
        #expect(list.map(\.id) == [word.id, made.id, "x-demo-commits"], "newest first")
        #expect(try await store.export("x-demo-commits", in: DemoData.commitsChat).saves.count == 1)

        try await store.discardExport(made.id, in: DemoData.commitsChat)
        let gone = try await store.export(made.id, in: DemoData.commitsChat)
        #expect(gone.status == "discarded" && !gone.keepsFile)
    }

    @Test func theDemosCreateFileCanBeCancelledWhileItWorks() async throws {
        let store = await demoStore(pace: 1, sleeper: { _ in try await Task.sleep(for: .milliseconds(800)) })
        let table = try await store.readView("v-commits-table", in: DemoData.commitsChat)
        let plan = try await store.previewExport(of: table, as: .csv, includeAnswers: false)
        async let made = store.renderExport(plan, in: DemoData.commitsChat)
        var cancelled = false
        for _ in 0..<60 where !cancelled {
            cancelled = try await store.cancelExport(plan, in: DemoData.commitsChat)
            if !cancelled { try await Task.sleep(for: .milliseconds(10)) }
        }
        let result = try await made
        #expect(cancelled && result.status == "cancelled" && !result.keepsFile)
        #expect(result.reason == "Cancelled. The partial file was removed.")
    }

    // MARK: - What the demo and the bridge offer

    @Test func laneTsMethodsAreOfferedAndNoneOfThemIsElevated() throws {
        let bridge = try RealBridge.info()
        #expect(laneTMethods.isSubset(of: bridge.methods), "Pebble 1.9.29's bridge offers every one")
        #expect(laneTMethods.isDisjoint(with: bridge.elevated))
        #expect(laneTMethods.isSubset(of: DemoClient.methods) && laneTMethods.isDisjoint(with: DemoClient.elevated))
        // Show on the Mac isn't built: `artifact_view_open` only stages a loopback page for the Mac's own window and
        // `view_stage` always refuses (app.py), so the demo offers neither.
        #expect(!DemoClient.methods.contains("artifact_view_open") && !DemoClient.methods.contains("view_stage"))
        #expect(bridge.elevated.isSuperset(of: ["artifact_view_open", "view_stage"]))
    }
}

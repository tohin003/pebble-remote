import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

/// Lane Y (fix 8): the calls behind the conversation's Details screen send exactly Pebble's params, guard with Face ID
/// what the person decides (F3, F5), read Pebble's answers, and the demo answers each tab as Pebble would.
@MainActor
struct DetailsKitTests {
    nonisolated static let goalJSON: JSONValue = [
        "id": "g1", "chat_id": "c1", "title": "Ship it", "revision": 3, "state": "active",
        "criteria": [
            ["id": "c1", "text": "Tests pass", "kind": "evidence", "status": "open", "origin": "human", "detail": "waiting for step s2"],
            ["id": "c2", "text": "Looks right", "kind": "human_check", "status": "candidate", "origin": "agent"],
        ],
        "steps": [["id": "s1", "title": "Write it", "status": "completed"]],
        "blockers": [["kind": "run", "label": "Needs your review"]],
        "progress": ["criteria_met": 0, "criteria_total": 1, "candidates": 1, "steps_completed": 1, "steps_total": 1],
        "note": "Goal records are operational records, not memory.",
    ]

    static func demo() async -> RemoteStore {
        let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
        let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
        store.clock = { Fixture.t0 }
        store.start()
        _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
        return store
    }

    // MARK: - Params and Face ID (FakeClient records every call)

    @Test func settlingAGoalAsksForFaceIDAndPausingDoesNot() async throws {
        let fake = FakeClient { _, _ in Self.goalJSON }
        let store = RemoteStore(client: fake)
        let goal = try #require(GoalRecord(json: Self.goalJSON, chatID: "c1"))
        _ = try await store.setGoalPaused(goal, true)
        _ = try await store.settleGoal(goal, done: true)
        _ = try await store.settleGoal(goal, done: false)
        _ = try await store.checkCriterion(goal.criteria[0], met: true, of: goal)
        _ = try await store.reviewCriterion(goal.criteria[1], accept: false, of: goal)
        let states = fake.calls("goal_state")
        #expect(states.map(\.elevated) == [false, true, true])
        #expect(states[0].params == ["chat_id": "c1", "goal_id": "g1", "revision": 3, "state": "paused"])
        #expect(states[1].params["state"] == "done" && states[2].params["state"] == "abandoned")
        #expect(fake.calls("goal_criterion_check").first?.elevated == true)
        #expect(fake.calls("goal_criterion_check").first?.params["met"] == true)
        #expect(fake.calls("goal_criterion_review").first?.params["decision"] == "reject")
        #expect(fake.calls("goal_criterion_review").first?.elevated == true)
    }

    @Test func agentsAreReadByTheirRootTaskAndCancellingAsksForFaceID() async throws {
        let fake = FakeClient { method, _ in
            method == "agent_list"
                ? ["root_run_id": "r1", "nodes": [["agent_id": "a1", "run_id": "r1", "name": "Helper", "task": "Look", "status": "running"]]]
                : .bool(true)
        }
        let store = RemoteStore(client: fake)
        let agents = try await store.agents(in: "c1", run: "r1")
        #expect(agents.map(\.id) == ["a1"] && agents[0].isActive && agents[0].canCancel)
        try await store.steer(agents[0], in: "c1", text: "Also check the footer")
        try await store.cancel(agents[0], in: "c1")
        #expect(fake.calls("agent_list").first?.params == ["chat_id": "c1", "run_id": "r1"])
        #expect(fake.calls("agent_steer").first?.params == ["chat_id": "c1", "run_id": "r1", "agent_id": "a1", "text": "Also check the footer"])
        #expect(fake.calls("agent_steer").first?.elevated == false)
        #expect(fake.calls("agent_cancel").first?.elevated == true)
    }

    @Test func contextAndRewindSendOnlyPebblesParams() async throws {
        let fake = FakeClient { method, params in
            switch method {
            case "context_inspect": ["basis": "last_request", "used": 166_500, "window": ["tokens": 272_000], "compact": ["available": true]]
            case "rewind_preview":
                ["chat_id": "c1", "run_id": "r1", "step": params["step"] ?? 0, "steps": 9, "digest": "d1",
                 "files": [["path": "a.ts", "status": "revert", "steps": [2], "diff": "-x\n+y"]]]
            case "rewind_apply": ["files": [["path": "a.ts", "status": "reverted", "verified": true]], "counts": ["reverted": 1]]
            default: ["status": "compacted", "archived": ["messages": 4, "tool_results": 2], "tokens": ["freed": 900]]
            }
        }
        let store = RemoteStore(client: fake)
        let use = try await store.contextUse(in: "c1", run: "r1")
        #expect(use.percent == 61 && use.canCompact)
        _ = try await store.compactContext(in: "c1")
        let plan = try await store.rewindPreview(in: "c1", run: "r1", step: 0)
        let result = try await store.rewind(plan)
        #expect(fake.calls("context_inspect").first?.params == ["chat_id": "c1", "run_id": "r1"])  // no surface: the bridge writes it
        #expect(fake.calls("context_compact").first?.params == ["chat_id": "c1"])
        #expect(fake.calls("rewind_preview").first?.params == ["chat_id": "c1", "run_id": "r1", "step": 0])
        let apply = try #require(fake.calls("rewind_apply").first)
        #expect(apply.elevated && apply.params == ["chat_id": "c1", "run_id": "r1", "step": 0, "digest": "d1"])
        #expect(apply.reason == "Rewind 1 file on your Mac")
        #expect(plan.restoring == 1 && result.restored == 1)
    }

    @Test func aTabGrantSendsPebblesTargetAndAsksForFaceID() async throws {
        let fake = FakeClient { _, _ in ["session_id": "s1", "state": "active", "pending": true] }
        let store = RemoteStore(client: fake)
        let tab = TabGrant(
            profile: "pebble", tabID: "1001", origins: ["https://docs.github.com"], actions: TabGrant.look, minutes: 15,
            screenshots: true)
        #expect(try await store.grant(tab, in: "c1") == .granted(pending: true))
        let call = try #require(fake.calls("screen_session_grant").first)
        #expect(call.elevated)
        #expect(call.params["id"] == "c1" && call.params["ttl"] == 900 && call.params["enable_screen"] == false)
        #expect(call.params["screenshots"] == false)  // screenshots are for a Chrome tab only
        #expect(call.params["target"] == ["kind": "browser", "profile": "pebble", "tab_id": "1001", "origins": ["https://docs.github.com"]])
    }

    @Test func screenControlOffComesBackAsPebblesQuestion() async throws {
        let fake = FakeClient { _, _ in
            ["status": "needs_screen_permission", "granted": false, "message": "Screen control is off.", "enable": ["available": false]]
        }
        let store = RemoteStore(client: fake)
        let tab = TabGrant(profile: "chrome", tabID: "7", origins: ["https://github.com"], actions: TabGrant.fill, minutes: 5)
        #expect(try await store.grant(tab, in: "c1") == .needsScreenControl(message: "Screen control is off.", canTurnOn: false))
    }

    // MARK: - Reading Pebble's answers

    @Test func contextUseCountsAsTheMacsRing() {
        let use = ContextUse(json: ["basis": "checkpoint", "total": 100, "window": ["tokens": 400], "compact": ["available": false, "reason": "live"]])
        #expect(use?.percent == 25 && use?.compactReason == "live")
        #expect(ContextUse(json: ["basis": "none", "compact": ["available": false]])?.percent == nil)
        #expect(ContextUse(json: ["basis": "last_request", "used": 3_000_000, "window": ["tokens": 1000]])?.percent == 999)
    }

    @Test func aGoalReadsPebblesShape() throws {
        let goal = try #require(GoalRecord(json: Self.goalJSON, chatID: "c1"))
        #expect(goal.criteria.map(\.id) == ["c1", "c2"] && goal.criteria[0].isEvidence && goal.criteria[1].isProposed)
        #expect(goal.blockers == ["Needs your review"] && goal.steps.first?.status == "completed")
        #expect(goal.isCurrent && !goal.isPaused && goal.progress.proposed == 1)
    }

    @Test func chromeStatusNeverKeepsThePairingCode() throws {
        let status = try #require(
            ChromeStatus(json: [
                "extension": ["connected": false, "present": true], "paused": false,
                "pairing": ["paired": false, "pending": ["code": "482913", "expires_in": 100, "attempts_left": 5]],
                "shared_tabs": [],
            ]))
        #expect(status.pairing && !status.connected)
        #expect(!String(describing: status).contains("482913"))
    }

    @Test func aRewindPlanOffersPebblesSteps() throws {
        let plan = try #require(
            RewindPlan(json: [
                "chat_id": "c1", "run_id": "r1", "step": 0, "steps": 9, "digest": "d",
                "timeline": [["step": 2, "files": ["a.ts"], "effects": 0]],
                "rewinds": [["rewind_id": "w1", "step": 0, "previous_step": 9, "applied": true]],
            ]))
        #expect(plan.choices == [0, 2, 9])
        #expect(plan.lastRewindUndoStep == 9 && !plan.undoesLastRewind)
    }

    // MARK: - The demo

    @Test func theDemosStepsCountAsTheirEndLine() async throws {
        let store = await Self.demo()
        let transcript = store.transcript(for: DemoData.commitsChat)
        _ = await eventually { transcript.recaps["r-commits"] != nil }
        let steps = try await store.runSteps("r-commits", in: DemoData.commitsChat)
        #expect(steps.listedSteps == 6 && steps.pebbleCount == 6 && steps.missingSteps == nil)
        #expect(transcript.recaps["r-commits"]?.steps == 6)
        #expect(steps.details.reasoning != nil)
    }

    @Test func theDemosGoalSettlesOnlyWhenPebbleSaysItCan() async throws {
        let store = await Self.demo()
        let list = try await store.goals(in: DemoData.themeChat)
        let found = list.first(where: \.isCurrent)
        let current = try #require(found)
        var goal = try await store.goal(current.id, in: DemoData.themeChat)
        await #expect(throws: RemoteCallError.self) { _ = try await store.settleGoal(goal, done: true) }
        #expect(store.notice?.message.hasPrefix("This goal is not done yet: ") == true)
        goal = try await store.reviewCriterion(goal.criteria[2], accept: true, of: goal)
        #expect(goal.criteria[2].status == "open")
        goal = try await store.checkCriterion(goal.criteria[2], met: true, of: goal)
        #expect(goal.criteria[2].status == "met" && goal.criteria[2].checkedBy == "human")
    }

    @Test func theDemosRewindIsPreviewedAppliedAndUndone() async throws {
        let store = await Self.demo()
        let plan = try await store.rewindPreview(in: DemoData.themeChat, run: DemoData.themeRun, step: 0)
        #expect(plan.restoring == 1 && plan.effects.count == 1)
        let result = try await store.rewind(plan)
        #expect(result.restored == 1)
        let after = try await store.rewindPreview(in: DemoData.themeChat, run: DemoData.themeRun, step: 0)
        #expect(after.restoring == 0 && after.lastRewindUndoStep == 9)
        let undo = try await store.rewindPreview(in: DemoData.themeChat, run: DemoData.themeRun, step: 9)
        #expect(undo.undoesLastRewind && undo.restoring == 1)
    }

    @Test func theDemosBrowserAndContextAnswerEveryTab() async throws {
        let store = await Self.demo()
        let chrome = try await store.chromeStatus()
        #expect(chrome.connected && chrome.sharedTabs.count == 1)
        try await store.pauseChrome(true)
        #expect(try await store.chromeStatus().paused)
        #expect(try await store.stopChrome() == 1)
        #expect(try await store.pebbleBrowserStatus().running)
        #expect(try await store.pebbleBrowserTabs().first?.origin == "https://docs.github.com")
        let use = try await store.contextUse(in: DemoData.themeChat, run: DemoData.themeRun)
        #expect(use.percent == 61 && use.canCompact)
        let compacted = try await store.compactContext(in: DemoData.themeChat)
        #expect(compacted.status == "compacted" && (compacted.context?.percent ?? 100) < 61)
        let grant = TabGrant(profile: "pebble", tabID: "1001", origins: ["https://docs.github.com"], actions: TabGrant.look, minutes: 15)
        #expect(try await store.grant(grant, in: DemoData.readmeChat).isScreenQuestion)
        // Permissions never change under a running task: the scripted run stops first.
        await #expect(throws: RemoteCallError.self) { _ = try await store.grant(grant, in: DemoData.readmeChat, enableScreen: true) }
        try? await store.stop(chat: DemoData.loginChat)
        _ = await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } }
        #expect(try await store.grant(grant, in: DemoData.readmeChat, enableScreen: true) == .granted(pending: true))
    }
}

extension TabGrantOutcome {
    var isScreenQuestion: Bool {
        if case .needsScreenControl = self { true } else { false }
    }
}

import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane R: finishing and recovering a task from the phone, against a FakeClient. Each call's method and params are
// Pebble's window's own (RunPanel.vue, ReconcilePanel.vue, ExecutionOutput.vue, ModelHandoff.vue, App.vue), which calls
// ask for Face ID, and what the store shows once Pebble answers. The phone never sends `surface` (the bridge writes it).

/// Every method lane R calls.
private let recoveryMethods: Set<String> = [
    "state", "get_chat", "run_resume", "run_held_tests", "run_held_finish", "run_held_accept", "screen_sessions",
    "screen_handoff_done", "screen_session_revoke", "run_readback", "run_reconcile", "undo", "shell_undo",
    "git_plan_propose", "shell_grant_add", "approve", "process_list", "process_terminal", "process_read",
    "process_stop", "process_input_human", "process_inspect", "process_dismiss", "model_select",
    "model_handoff_preview", "model_handoff_approve", "model_handoff_start",
]

/// What the fake Pebble answers with, which a test may change.
private final class Answers: Sendable {
    private let value: Mutex<[String: JSONValue]>
    init(_ value: [String: JSONValue] = [:]) { self.value = Mutex(value) }
    subscript(_ method: String) -> JSONValue? {
        get { value.withLock { $0[method] } }
        set { value.withLock { $0[method] = newValue } }
    }
}

@MainActor
private func recoveryStore(
    runs: [JSONValue], actions: [JSONValue] = [], workspace: String? = "/Users/me/Projects/pebble-web",
    elevated: Set<String> = ["approve", "run_held_accept", "run_held_finish", "model_handoff_approve"],
    unlockSeconds: Int? = nil, answers: Answers = Answers(),
    refuse: @escaping @Sendable (String, JSONValue) -> RemoteCallError? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let state = Fixture.stateJSON(
        chats: [Fixture.chatRow("c1", "Fix the login redirect loop", workspace: workspace)], runs: runs)
    var detail = Fixture.chatDetail(actions: actions, runs: runs).object ?? [:]
    detail["workspace"] = workspace.map(JSONValue.string) ?? .null
    let chat = JSONValue.object(detail)
    let fake = FakeClient { method, params in
        if let refusal = refuse(method, params) { throw refusal }
        if let answer = answers[method] { return answer }
        switch method {
        case "state": return state
        case "get_chat", "remote.chat_tail": return chat
        default: return .bool(true)
        }
    }
    let store = RemoteStore(client: fake)
    store.clock = { Fixture.at(60) }
    fake.push(
        .welcome(
            BridgeInfo(
                bridgeVersion: "0.5", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "1.9.28",
                methods: recoveryMethods, elevated: elevated, resumed: false, unlockSeconds: unlockSeconds)))
    _ = await eventually { store.pebble != nil }
    let transcript = store.transcript(for: "c1")
    _ = await eventually { !transcript.isLoading }
    return (store, fake)
}

private func refused(_ message: String, code: String? = nil) -> RemoteCallError {
    .refused(PersonFacingError(message: message, code: code))
}

// MARK: - A held task

@MainActor
@Test func aHeldTasksThreeDecisionsCallPebblesRoutes() async throws {
    let (store, fake) = await recoveryStore(runs: [Fixture.runRow("r1", chat: "c1", state: "verification_required")])
    let transcript = store.transcript(for: "c1")
    let task = try #require(transcript.task)
    #expect(task.isHeld && task.hasProject && task.waitsForDecision && !task.canResume)
    #expect(transcript.items.contains(.task(task)))
    #expect(store.waiting.contains(.task(task)))
    #expect(store.chats.first?.waitingCount == 1)

    try await store.runHeldTests(task)
    let tests = try #require(fake.calls("run_held_tests").last)
    #expect(tests.params == ["id": "c1", "run_id": "r1"] && !tests.elevated)

    try await store.askPebbleToFinish(task)
    let finish = try #require(fake.calls("run_held_finish").last)
    #expect(finish.params == ["id": "c1", "run_id": "r1"] && finish.elevated)  // the bridge lists it (3.6)

    try await store.acceptUnverified(task)
    let accept = try #require(fake.calls("run_held_accept").last)
    #expect(accept.params == ["id": "c1", "run_id": "r1"] && accept.elevated)
    #expect(accept.reason == "Accept as unverified: Fix the login redirect loop")
    // Each returns once the store read the conversation again.
    #expect(fake.methods.filter { $0 == "get_chat" }.count >= 4)
}

@MainActor
@Test func acceptingAsUnverifiedAsksFaceIDEvenWhenTheBridgeDoesNotListIt() async throws {
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "verification_required")], elevated: [])
    let task = try #require(store.transcript(for: "c1").task)
    try await store.acceptUnverified(task)
    #expect(fake.calls("run_held_accept").last?.elevated == true)
    try await store.askPebbleToFinish(task)
    #expect(fake.calls("run_held_finish").last?.elevated == false)  // plain, unless the bridge asks
}

@MainActor
@Test func aHeldDecisionPebbleRefusesShowsItsWords() async throws {
    let (store, _) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "verification_required")],
        refuse: { method, _ in method == "run_held_tests" ? refused("Wait for the current task to finish first.") : nil })
    let task = try #require(store.transcript(for: "c1").task)
    await #expect(throws: RemoteCallError.self) { try await store.runHeldTests(task) }
    #expect(store.notice?.message == "Wait for the current task to finish first.")
}

// MARK: - Resume

@MainActor
@Test func resumeSendsNewLimitsOnlyAfterTheTaskReachedItsLimit() async throws {
    let (store, fake) = await recoveryStore(runs: [Fixture.runRow("r1", chat: "c1", state: "failed", error: "No reply.")])
    let failed = try #require(store.transcript(for: "c1").task)
    #expect(failed.canResume && !failed.needsLimits && failed.showsInConversation)
    try await store.resume(failed, limits: RunLimits(maxSteps: 200, maxSeconds: 3600))
    #expect(fake.calls("run_resume").last?.params == ["id": "c1", "run_id": "r1"])

    let limited = TaskAttention(chatID: "c1", chatTitle: "Fix", runID: "r2", state: .budgetExhausted)
    try await store.resume(limited, limits: RunLimits(maxSteps: 200, maxSeconds: 3600))
    #expect(
        fake.calls("run_resume").last?.params
            == ["id": "c1", "run_id": "r2", "limits": ["max_steps": 200, "max_seconds": 3600]])
    try await store.resume(limited)
    #expect(
        fake.calls("run_resume").last?.params
            == ["id": "c1", "run_id": "r2", "limits": ["max_steps": 128, "max_seconds": 1800]])  // Pebble's first values
    #expect(fake.calls("run_resume").allSatisfy { !$0.elevated })
}

@Test func runLimitsAreThoseOfPebblesRange() {
    #expect(RunLimits.resumeDefaults.isValid)
    #expect(RunLimits(maxSteps: 1, maxSeconds: 1).isValid && RunLimits(maxSteps: 256, maxSeconds: 86_400).isValid)
    #expect(!RunLimits(maxSteps: 0, maxSeconds: 60).isValid)
    #expect(!RunLimits(maxSteps: 257, maxSeconds: 60).isValid)
    #expect(!RunLimits(maxSteps: 64, maxSeconds: 86_401).isValid)
}

// MARK: - Paused windows and uncertain outcomes

private let sessions: JSONValue = [
    [
        "session_id": "s-mail", "run_id": "r1", "kind": "app", "state": "interrupted",
        "target": ["kind": "app", "bundle_id": "com.apple.mail"], "actions": ["press"], "pending": false,
    ],
    [
        "session_id": "s-notes", "run_id": "r1", "kind": "app", "state": "active",
        "target": ["kind": "app", "bundle_id": "com.apple.Notes"], "actions": ["press"], "pending": false,
    ],
]

@MainActor
@Test func pausedWindowsAreReadQuietlyAndDoneMarksTheTaskChecked() async throws {
    let answers = Answers(["screen_sessions": sessions])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "needs_reconciliation")], answers: answers)
    await store.loadPausedWindows(in: "c1")
    #expect(fake.calls("screen_sessions").last?.params == ["id": "c1"])
    let task = try #require(store.transcript(for: "c1").task)
    #expect(task.needsCheck && task.pausedWindows.map(\.id) == ["s-mail"] && task.pausedWindows.first?.appName == "mail")
    #expect(store.waiting.contains(.task(task)))

    answers["screen_sessions"] = []
    try await store.markWindowDone(try #require(task.pausedWindows.first))
    #expect(fake.calls("screen_handoff_done").last?.params == ["session_id": "s-mail"])
    let checked = try #require(store.transcript(for: "c1").task)
    #expect(checked.windowChecked && checked.pausedWindows.isEmpty)
}

@MainActor
@Test func endAccessRevokesTheWindowWithoutCheckingTheTask() async throws {
    let answers = Answers(["screen_sessions": sessions])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "needs_reconciliation")], answers: answers)
    await store.loadPausedWindows(in: "c1")
    let window = try #require(store.transcript(for: "c1").task?.pausedWindows.first)
    answers["screen_sessions"] = []
    try await store.endAccess(window)
    #expect(fake.calls("screen_session_revoke").last?.params == ["session_id": "s-mail"])
    #expect(store.transcript(for: "c1").task?.windowChecked == false)
}

@MainActor
@Test func aLockedPhoneReadsNoWindowsOrCommandsOnItsOwn() async throws {
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "needs_reconciliation")], unlockSeconds: 900,
        answers: Answers(["screen_sessions": sessions]))
    #expect(!store.readsQuietly)
    await store.loadPausedWindows(in: "c1")
    store.watchCommands(in: "c1")
    try await Task.sleep(for: .milliseconds(50))
    #expect(fake.calls("screen_sessions").isEmpty && fake.calls("process_list").isEmpty)
    // Unlocked (any elevated call counts), the same reads go ahead.
    fake.push(.unlocked(until: Fixture.at(600)))
    _ = await eventually { store.readsQuietly }
    await store.loadPausedWindows(in: "c1")
    #expect(fake.calls("screen_sessions").count == 1)
}

@MainActor
@Test func noPausedWindowIsReadWithoutAnUncertainStep() async throws {
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "failed")], answers: Answers(["screen_sessions": sessions]))
    await store.loadPausedWindows(in: "c1")
    #expect(fake.calls("screen_sessions").isEmpty)
}

@MainActor
@Test func uncertainOutcomesSettleFromReadbackOrFromTheReport() async throws {
    let answers = Answers([
        "run_readback": [
            "items": [
                [
                    "call_id": "4:write", "tool": "WriteFile", "kind": "file", "action_id": "a1", "verdict": "occurred",
                    "basis": "after_present", "authorization": "none",
                ],
                [
                    "call_id": "6:press", "tool": "ScreenAct", "kind": .null, "action_id": .null, "verdict": "unknown",
                    "basis": "no_broker_action", "authorization": "none",
                ],
            ],
            "authorization": "none",
        ]
    ])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "needs_reconciliation")], answers: answers)
    let task = try #require(store.transcript(for: "c1").task)
    let page = try await store.readback(task)
    #expect(fake.calls("run_readback").last?.params == ["id": "c1", "run_id": "r1"])
    #expect(!page.waitsForTask && page.items.map(\.callID) == ["4:write", "6:press"])
    let written = try #require(page.items.first), pressed = try #require(page.items.last)
    #expect(written.tool == "WriteFile" && written.kind == "file" && written.canSettleFromReadback)
    #expect(pressed.kind == nil && !pressed.canSettleFromReadback && pressed.basis == "no_broker_action")

    try await store.settleFromReadback(written)
    #expect(
        fake.calls("run_reconcile").last?.params
            == ["id": "c1", "run_id": "r1", "call_id": "4:write", "effect": "readback", "note": ""])
    try await store.recordReport(pressed, .didNotOccur, note: "  The message isn't in Sent.  ")
    #expect(
        fake.calls("run_reconcile").last?.params
            == [
                "id": "c1", "run_id": "r1", "call_id": "6:press", "effect": "did_not_occur",
                "note": "The message isn't in Sent.",
            ])
    #expect(fake.calls("run_reconcile").allSatisfy { !$0.elevated })
}

@MainActor
@Test func whileAnotherTaskRunsTheReadbackWaitsWithoutAFailure() async throws {
    let (store, _) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "needs_reconciliation")],
        refuse: { method, _ in
            method == "run_readback" ? refused("Stop the active run before reading back its outcomes.") : nil
        })
    let task = try #require(store.transcript(for: "c1").task)
    let page = try await store.readback(task)
    #expect(page.waitsForTask && page.items.isEmpty)
    #expect(store.notice == nil)
}

// MARK: - Undo

private func applied(_ id: String, kind: String, payload: JSONValue, status: String = "applied", at seconds: Double)
    -> JSONValue
{
    Fixture.action(id, kind: kind, status: status, payload: payload, at: seconds)
}

private let undoable: [JSONValue] = [
    applied(
        "a-edit", kind: "edit", payload: ["path": "src/App.vue", "baseline": "1f", "result": ["hash": "2e"]], at: 10),
    applied("a-cmd", kind: "command", payload: ["command": "npm run fmt", "result": ["undo": "available"]], at: 11),
    applied("a-cmd-kept", kind: "command", payload: ["command": "ls", "result": ["exit_code": 0]], at: 12),
    applied(
        "a-shell", kind: "shell",
        payload: ["command": "rm notes.txt", "result": ["snapshot": ["id": "0123456789abcdef0123456789abcdef", "undoable": true]]],
        at: 13),
    applied(
        "a-file", kind: "file",
        payload: ["path": "/Users/me/notes.txt", "result": ["undoable": true, "snapshot": "fedcba9876543210fedcba9876543210"]],
        at: 14),
    applied("a-git", kind: "git", payload: ["operation": "commit", "result": ["receipt_id": "rcp-7"]], at: 15),
    applied("a-git-undo", kind: "git", payload: ["operation": "undo", "result": ["receipt_id": "rcp-8"]], at: 16),
    applied("a-undone", kind: "edit", payload: ["path": "src/Old.vue"], status: "undone", at: 17),
    applied("a-pending", kind: "edit", payload: ["path": "src/New.vue"], status: "pending", at: 18),
]

@MainActor
@Test func undoShowsWherePebbleOffersItAndUsesItsFourRoutes() async throws {
    let answers = Answers(["shell_undo": ["restored": ["/Users/me/notes.txt"], "failed": []]])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "completed")], actions: undoable, answers: answers)
    let records = store.transcript(for: "c1").items.compactMap { item -> ActionRecord? in
        if case .action(let record) = item { record } else { nil }
    }
    #expect(records.map(\.actionID) == ["a-edit", "a-cmd", "a-shell", "a-file", "a-git", "a-undone"])
    let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.actionID, $0) })
    #expect(byID["a-edit"]?.undo == .edit && byID["a-cmd"]?.undo == .command)
    #expect(byID["a-shell"]?.undo == .change(snapshotID: "0123456789abcdef0123456789abcdef"))
    #expect(byID["a-file"]?.undo == .change(snapshotID: "fedcba9876543210fedcba9876543210"))
    #expect(byID["a-git"]?.undo == .gitPlan(receiptID: "rcp-7"))
    #expect(byID["a-undone"]?.undo == nil && byID["a-undone"]?.isUndone == true)

    #expect(try await store.undo(try #require(byID["a-edit"])) == .editUndone)
    let edit = try #require(fake.calls("undo").last)
    #expect(edit.params == ["id": "c1", "action_id": "a-edit"] && edit.elevated && edit.reason == "Undo: Change App.vue")
    #expect(try await store.undo(try #require(byID["a-cmd"])) == .commandUndone)
    #expect(fake.calls("undo").last?.params == ["id": "c1", "action_id": "a-cmd"])

    #expect(try await store.undo(try #require(byID["a-shell"])) == .changeUndone)
    let shell = try #require(fake.calls("shell_undo").last)
    #expect(shell.params == ["snapshot_id": "0123456789abcdef0123456789abcdef"] && shell.elevated)
    answers["shell_undo"] = ["restored": [], "failed": [["path": "/Users/me/notes.txt"]]]
    #expect(try await store.undo(try #require(byID["a-file"])) == .someChangesNotUndone)

    #expect(try await store.undo(try #require(byID["a-git"])) == .undoPlanReady)
    let git = try #require(fake.calls("git_plan_propose").last)
    #expect(git.params == ["id": "c1", "operation": "undo", "receipt_id": "rcp-7"] && !git.elevated)
}

@MainActor
@Test func aCardFromAnEarlierTurnClosesThatTurn() async throws {
    var world = PebbleWorld()
    world.load(StateDTO(json: Fixture.stateJSON(runs: [Fixture.runRow("r1", chat: "c1", state: "completed", created: 1)]))!)
    world.load(
        ChatDetailDTO(
            json: Fixture.chatDetail(
                messages: [
                    Fixture.message("m1", "user", "Change the title", at: 0),
                    Fixture.message("m2", "assistant", "Done.", at: 20, run: "r1"),
                    Fixture.message("m3", "user", "Thanks", at: 40),
                ],
                actions: [applied("a-edit", kind: "edit", payload: ["path": "src/App.vue"], at: 10)],
                runs: [Fixture.runRow("r1", chat: "c1", state: "completed", created: 1)]))!)
    let ids = world.transcriptItems(for: "c1").map(\.id)
    let card = try #require(ids.firstIndex(of: "x/c1/a-edit"))
    #expect(card > (ids.firstIndex(of: "m/m2") ?? .max) && card < (ids.firstIndex(of: "m/m3") ?? -1))
}

// MARK: - Always allow

@MainActor
@Test func alwaysAllowSavesEachHostAndFolderThenApprovesOnce() async throws {
    let shell = Fixture.action(
        "a-sh", kind: "shell",
        payload: [
            "command": "curl -o data.json https://api.example.com/data", "always_offered": true,
            "hosts": ["api.example.com", "cdn.example.com"], "folders": ["/Users/me/Downloads"],
        ])
    let (store, fake) = await recoveryStore(runs: [Fixture.runRow("r1", chat: "c1", state: "waiting_approval")], actions: [shell])
    guard case .review(let card)? = store.waiting.first else {
        Issue.record("expected the card")
        return
    }
    #expect(card.offersAlwaysAllow)
    #expect(
        card.alwaysAllowGrants == [
            AlwaysAllowGrant(kind: "hosts", value: "api.example.com"),
            AlwaysAllowGrant(kind: "hosts", value: "cdn.example.com"),
            AlwaysAllowGrant(kind: "folders", value: "/Users/me/Downloads"),
        ])
    try await store.alwaysAllow(card)
    let grants = fake.calls("shell_grant_add")
    #expect(
        grants.map(\.params) == [
            ["kind": "hosts", "value": "api.example.com", "scope": "always"],
            ["kind": "hosts", "value": "cdn.example.com", "scope": "always"],
            ["kind": "folders", "value": "/Users/me/Downloads", "scope": "always"],
        ])
    #expect(grants.allSatisfy { $0.elevated } && grants.first?.reason?.hasPrefix("Always allow: Run curl") == true)
    #expect(fake.calls("approve").map(\.params) == [["id": "c1", "action_id": "a-sh"]])
    #expect(fake.methods.lastIndex(of: "shell_grant_add")! < fake.methods.lastIndex(of: "approve")!)
}

@MainActor
@Test func alwaysAllowOnAFileCardAllowsItsFolder() {
    let file = ReviewItem(
        chatID: "c1", chatTitle: "Notes", actionID: "a1", kind: .file, title: "Write notes.txt",
        payload: ["path": "/Users/me/Documents/notes.txt", "always_offered": true])
    #expect(file.offersAlwaysAllow && file.alwaysAllowGrants == [AlwaysAllowGrant(kind: "folders", value: "/Users/me/Documents")])
    let asked = ReviewItem(
        chatID: "c1", chatTitle: "Notes", actionID: "a2", kind: .shell, title: "Run rm",
        payload: ["command": "rm -rf build", "always_offered": false])
    #expect(!asked.offersAlwaysAllow)
    let command = ReviewItem(
        chatID: "c1", chatTitle: "Notes", actionID: "a3", kind: .command, title: "Run ls", payload: ["always_offered": true])
    #expect(!command.offersAlwaysAllow)  // only Shell and file cards
}

@MainActor
@Test func aGrantPebbleRefusesIsShownAndTheCardIsStillApprovedOnce() async throws {
    let shell = Fixture.action(
        "a-sh", kind: "shell", payload: ["command": "touch ~/.ssh/x", "always_offered": true, "folders": ["/Users/me/.ssh"]])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "waiting_approval")], actions: [shell],
        refuse: { method, _ in
            method == "shell_grant_add" ? refused("/Users/me/.ssh is asked about every time; it cannot be allowed always.") : nil
        })
    guard case .review(let card)? = store.waiting.first else { return }
    try await store.alwaysAllow(card)
    #expect(fake.calls("approve").count == 1)
    #expect(store.notice?.message == "/Users/me/.ssh is asked about every time; it cannot be allowed always.")
}

@MainActor
@Test func cancellingFaceIDForAGrantApprovesNothing() async throws {
    let shell = Fixture.action("a-sh", kind: "shell", payload: ["command": "ls", "always_offered": true, "hosts": ["a.example"]])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "waiting_approval")], actions: [shell],
        refuse: { method, _ in method == "shell_grant_add" ? .cancelledByPerson : nil })
    guard case .review(let card)? = store.waiting.first else { return }
    await #expect(throws: RemoteCallError.cancelledByPerson) { try await store.alwaysAllow(card) }
    #expect(fake.calls("approve").isEmpty && store.notice == nil)
}

// MARK: - Commands

private let jobs: JSONValue = [
    ["id": "p-dev", "run_id": "r1", "state": "running", "outcome_uncertain": 0, "inspection_recorded": 0],
    ["id": "p-sync", "run_id": "r1", "state": "unknown", "outcome_uncertain": 1, "inspection_recorded": 0],
    ["id": "p-done", "run_id": "r1", "state": "succeeded", "outcome_uncertain": 0, "inspection_recorded": 0],
]

@MainActor
@Test func commandsAreReadOnPebblesEventsAndShowWhenTheyNeedThePerson() async throws {
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "completed")], answers: Answers(["process_list": jobs]))
    store.watchCommands(in: "c1")
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { transcript.items.contains { $0.id == "p/p-dev" } })
    #expect(fake.calls("process_list").first?.params == ["id": "c1"])
    let shown = transcript.items.compactMap { item -> ProcessJob? in if case .command(let job) = item { job } else { nil } }
    #expect(shown.map(\.id) == ["p-dev", "p-sync"])  // a settled command with a known outcome stays out
    #expect(shown[0].isLive && !shown[0].needsInspection && !shown[0].canForgetOutput)
    #expect(!shown[1].isLive && shown[1].needsInspection && !shown[1].canForgetOutput)

    let reads = fake.calls("process_list").count
    fake.push("process", ["chat_id": "c1", "run_id": "r1", "process_id": "p-dev", "state": "stopped"])
    #expect(await eventually { fake.calls("process_list").count > reads })
    fake.push("process", ["chat_id": "c2", "run_id": "r9", "process_id": "p-x", "state": "stopped"])
    try await Task.sleep(for: .milliseconds(30))
    #expect(fake.calls("process_list").count == reads + 1)  // another conversation's event reads nothing here
}

@MainActor
@Test func aCommandIsStoppedTypedIntoInspectedReadAndForgotten() async throws {
    let answers = Answers([
        "process_list": jobs,
        "process_terminal": ["process_id": "p-dev", "interactive": true, "live": true, "echo": false, "authorization": "none"],
        "process_inspect": ["process_id": "p-sync", "inspection_recorded": true, "authorization": "none"],
        "process_read": [
            "process_id": "p-dev", "state": "running", "untrusted_process_output": "Password: ", "next_after": 10,
            "more": true, "output_complete": false, "controls_removed": 2,
        ],
    ])
    let (store, fake) = await recoveryStore(
        runs: [Fixture.runRow("r1", chat: "c1", state: "completed")], elevated: ["process_input_human"], answers: answers)
    await store.loadCommands(in: "c1")
    let dev = try #require(store.transcript(for: "c1").items.compactMap { item -> ProcessJob? in
        if case .command(let job) = item, job.id == "p-dev" { job } else { nil }
    }.first)
    let target: JSONValue = ["id": "c1", "run_id": "r1", "process_id": "p-dev"]

    let terminal = try await store.terminal(of: dev)
    #expect(terminal.takesTyping && terminal.isSecret)
    #expect(fake.calls("process_terminal").last?.params == target)

    try await store.typeLine("hunter2", into: dev)
    let typed = fake.calls("process_input_human")
    #expect(typed.map(\.params) == [
        ["id": "c1", "run_id": "r1", "process_id": "p-dev", "text": "hunter2"],
        ["id": "c1", "run_id": "r1", "process_id": "p-dev", "key": "enter"],
    ])
    #expect(typed.allSatisfy { $0.elevated })
    try await store.sendKey(.ctrlC, to: dev)
    #expect(fake.calls("process_input_human").last?.params == ["id": "c1", "run_id": "r1", "process_id": "p-dev", "key": "ctrl_c"])

    let page = try await store.readOutput(of: dev)
    #expect(fake.calls("process_read").last?.params == ["id": "c1", "run_id": "r1", "process_id": "p-dev", "after": 0, "limit": 4000])
    #expect(page.text == "Password: " && page.next == 10 && page.more && page.incomplete && page.controlsRemoved == 2)

    try await store.stopCommand(dev)
    #expect(fake.calls("process_stop").last?.params == target && fake.calls("process_stop").last?.elevated == false)

    let sync = ProcessJob(id: "p-sync", chatID: "c1", runID: "r1", state: "unknown", outcomeUncertain: true)
    try await store.recordInspection(of: sync, .noEffectObserved, note: " Nothing copied. ")
    #expect(
        fake.calls("process_inspect").last?.params
            == ["id": "c1", "run_id": "r1", "process_id": "p-sync", "observation": "no_effect_observed", "note": "Nothing copied."])
    try await store.forgetOutput(of: sync)
    #expect(fake.calls("process_dismiss").last?.params == ["id": "c1", "run_id": "r1", "process_id": "p-sync"])
}

@MainActor
@Test func aTerminalIsReadOnTheScreensOwnOnlyWhenTheBridgeAsksNoFaceIDForIt() async throws {
    let answers = Answers(["process_terminal": ["interactive": true, "live": true, "echo": true]])
    let dev = ProcessJob(id: "p-dev", chatID: "c1", runID: "r1", state: "running")
    let (quiet, quietFake) = await recoveryStore(runs: [], answers: answers)
    #expect(quiet.readsTerminalsQuietly)
    #expect(await quiet.readTerminal(of: dev)?.takesTyping == true)
    #expect(quietFake.calls("process_terminal").last?.elevated == false)

    let (asks, asksFake) = await recoveryStore(runs: [], elevated: ["process_terminal"], answers: answers)
    #expect(!asks.readsTerminalsQuietly)
    #expect(await asks.readTerminal(of: dev) == nil)
    #expect(asksFake.calls("process_terminal").isEmpty)
    _ = try await asks.terminal(of: dev)  // on the person's tap: with Face ID
    #expect(asksFake.calls("process_terminal").last?.elevated == true)
}

// MARK: - Continue with the new model

private let plan: JSONValue = [
    "plan_fingerprint": "fp-1", "source_class": "cloud:chatgpt", "destination_class": "cloud:claude",
    "destination_fingerprint_prefix": "0123456789abcdef0123456789abcdef0123", "counts": [
        "user": ["cloud:chatgpt": 2], "assistant": ["cloud:chatgpt": 2, "device": 1], "host": ["cloud:chatgpt": 1],
    ], "withheld_ids": ["m-7"], "released_classes": [], "send_count": 6, "authorization": "none",
]

@MainActor
@Test func aModelChangeOffersToContinueATaskThatCannotResume() async throws {
    let (store, fake) = await recoveryStore(runs: [
        Fixture.runRow("r0", chat: "c1", state: "interrupted", created: 0),
        Fixture.runRow("r1", chat: "c1", state: "failed", created: 5),
        Fixture.runRow("r2", chat: "c1", state: "completed", created: 9),
    ])
    let transcript = store.transcript(for: "c1")
    #expect(!transcript.items.contains { if case .handoff = $0 { true } else { false } })
    try await store.selectModel("claude", from: "c1")
    #expect(fake.calls("model_select").last?.params == ["profile_id": "claude"])
    #expect(transcript.items.contains(.handoff(HandoffOffer(chatID: "c1", runID: "r1"))))  // the newest such task
    store.dismissHandoff(in: "c1")
    #expect(!transcript.items.contains { if case .handoff = $0 { true } else { false } })
}

@MainActor
@Test func aModelChangeInAConversationWhoseTasksEndedOffersNothing() async throws {
    let (store, _) = await recoveryStore(runs: [Fixture.runRow("r1", chat: "c1", state: "completed")])
    try await store.selectModel("claude", from: "c1")
    #expect(!store.transcript(for: "c1").items.contains { if case .handoff = $0 { true } else { false } })
}

@MainActor
@Test func theHandoffIsPreviewedApprovedWithFaceIDAndStarted() async throws {
    let answers = Answers([
        "model_handoff_preview": plan,
        "model_handoff_approve": ["approved": true, "plan_fingerprint": "fp-1", "authorization": "none"],
        "model_handoff_start": ["chat_id": "c9", "run_id": "r9", "sent": 6, "withheld": 1, "authorization": "none"],
    ])
    let (store, fake) = await recoveryStore(runs: [Fixture.runRow("r1", chat: "c1", state: "failed")], answers: answers)
    try await store.selectModel("chatgpt", from: "c1")
    let offer = HandoffOffer(chatID: "c1", runID: "r1")
    let reviewed = try await store.previewHandoff(offer)
    #expect(fake.calls("model_handoff_preview").last?.params == ["id": "c1", "run_id": "r1", "profile_id": "chatgpt"])
    #expect(reviewed.fingerprint == "fp-1" && reviewed.classes == ["cloud:chatgpt", "device"])
    #expect(reviewed.rows.map(\.role) == ["assistant", "host", "user"] && reviewed.rows[0].cells == [2, 1])
    #expect(reviewed.total == 6 && reviewed.withheld == ["m-7"] && reviewed.uploads)
    #expect(reviewed.destinationPrefix.count == 32)

    try await store.approveHandoff(reviewed, for: offer)
    let approval = try #require(fake.calls("model_handoff_approve").last)
    #expect(approval.params == ["id": "c1", "plan_fingerprint": "fp-1"] && approval.elevated)
    #expect(approval.reason == "Approve this handoff")

    let chat = try await store.startHandoff(reviewed, for: offer)
    #expect(chat == "c9")
    #expect(fake.calls("model_handoff_start").last?.params == ["id": "c1", "plan_fingerprint": "fp-1"])
    #expect(!store.transcript(for: "c1").items.contains { if case .handoff = $0 { true } else { false } })
}

@MainActor
@Test func aHandoffPebbleDidNotConfirmSaysSoInItsWindowsWords() async throws {
    let answers = Answers([
        "model_handoff_preview": ["plan_fingerprint": ""],
        "model_handoff_approve": ["approved": true, "plan_fingerprint": "another"],
        "model_handoff_start": ["chat_id": "c9"],
    ])
    let (store, _) = await recoveryStore(runs: [Fixture.runRow("r1", chat: "c1", state: "failed")], answers: answers)
    let offer = HandoffOffer(chatID: "c1", runID: "r1")
    await #expect(throws: RemoteCallError.self) { try await store.previewHandoff(offer) }
    #expect(store.notice?.message == "Pebble could not prepare this handoff. Nothing was sent.")
    let reviewed = try #require(HandoffPlan(json: plan))
    await #expect(throws: RemoteCallError.self) { try await store.approveHandoff(reviewed, for: offer) }
    #expect(store.notice?.message == "Pebble did not confirm approval of this exact handoff. Nothing was sent.")
    await #expect(throws: RemoteCallError.self) { try await store.startHandoff(reviewed, for: offer) }
    #expect(store.notice?.message.hasPrefix("Pebble did not report a new run.") == true)
}

@Test func theHandoffOfferWaitsWhileATaskRuns() {
    var world = Fixture.world(
        runs: [
            Fixture.runRow("r1", chat: "c1", state: "failed", created: 0),
            Fixture.runRow("r2", chat: "c2", state: "running", created: 5),
        ], active: "c2", activeRun: "r2")
    world.offerHandoff(in: "c1")
    #expect(world.handoffOffers["c1"] == HandoffOffer(chatID: "c1", runID: "r1"))
    #expect(world.handoffOffer(for: "c1") == nil)  // Pebble's window: `!state.active`
    world.apply(Fixture.event("run", ["chat_id": "c2", "run_id": "r2", "state": "completed"], at: 10))
    #expect(world.handoffOffer(for: "c1") == HandoffOffer(chatID: "c1", runID: "r1"))
}

// MARK: - When the task shows

@Test(arguments: [
    ("interrupted", true, false), ("failed", true, false), ("budget_exhausted", true, false),
    ("verification_required", true, true), ("needs_reconciliation", true, true), ("paused", false, false),
    ("stopped", false, false),
])
func aTaskShowsUnderTheConversationAndOnReviewsAsPebbleSaysIt(state: String, shows: Bool, waits: Bool) throws {
    let world = Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: state)])
    let task = try #require(world.taskAttention(for: "c1"))
    #expect(task.showsInConversation == shows && task.waitsForDecision == waits)
    #expect(world.transcriptItems(for: "c1").contains(.task(task)) == shows)
    #expect(world.waitingItems().contains(.task(task)) == waits)
}

@Test func aFinishedOrWorkingTaskShowsNothing() {
    #expect(Fixture.world(runs: [Fixture.runRow("r1", chat: "c1", state: "completed")]).taskAttention(for: "c1") == nil)
    let working = Fixture.world(
        runs: [
            Fixture.runRow("r0", chat: "c1", state: "failed", created: 0),
            Fixture.runRow("r1", chat: "c1", state: "running", created: 5),
        ], active: "c1", activeRun: "r1")
    #expect(working.taskAttention(for: "c1") == nil)  // the live run is the current one (RunPanel `current`)
}

@Test func aHeldTaskInCompanionHasNoProjectToTest() throws {
    var world = PebbleWorld()
    world.load(
        StateDTO(
            json: Fixture.stateJSON(
                chats: [Fixture.chatRow("c1", "Plan a trip")],
                runs: [Fixture.runRow("r1", chat: "c1", state: "verification_required")]))!)
    let task = try #require(world.taskAttention(for: "c1"))
    #expect(task.isHeld && !task.hasProject)
}

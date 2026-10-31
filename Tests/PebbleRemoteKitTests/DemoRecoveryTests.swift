import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// "Try the demo" with lane R's work, end to end through the real store: a held task's three decisions, the uncertain
// step with its paused Mail window, the running command, the failed task's Resume and its model handoff, and an Undo.
// Pace 0: scripts run without waiting.

@MainActor
private func demoStore() async -> RemoteStore {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.clock = { Fixture.t0 }
    store.start()
    _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
    return store
}

/// The demo opens with a task working, and Pebble decides on held tasks only while none runs.
@MainActor
private func stopTheLoginRun(_ store: RemoteStore) async throws {
    try await store.stop(chat: DemoData.loginChat)
    #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } && !store.isPebbleWorking })
}

@MainActor
private func replies(_ transcript: Transcript) -> [MessageItem] {
    transcript.items.compactMap { if case .message(let m) = $0, m.role == .assistant { m } else { nil } }
}

@MainActor
private func task(_ store: RemoteStore, _ chat: ChatID) async throws -> TaskAttention {
    let transcript = store.transcript(for: chat)
    _ = await eventually { transcript.task != nil }
    return try #require(transcript.task)
}

@MainActor
@Test func theDemosHeldTaskRunsItsTestsThroughAReview() async throws {
    let store = await demoStore()
    let held = try await task(store, DemoData.themeChat)
    #expect(held.isHeld && held.hasProject && held.note == "The change to src/settings/ThemeToggle.tsx has no passing test run yet.")
    await #expect(throws: RemoteCallError.self) { try await store.runHeldTests(held) }
    #expect(store.notice?.message == "Wait for the current task to finish first.")
    try await stopTheLoginRun(store)

    try await store.runHeldTests(held)
    let transcript = store.transcript(for: DemoData.themeChat)
    #expect(transcript.task == nil)  // waiting for the tests' review now
    let card = try #require(store.waiting.lazy.compactMap { item -> ReviewItem? in
        if case .review(let card) = item, card.chatID == DemoData.themeChat { card } else { nil }
    }.first)
    #expect(card.kind == .tests && card.title == "Run isolated tests")
    try await store.approve(card)
    #expect(await eventually { replies(transcript).last?.text.hasSuffix("The change is verified.") == true })
    #expect(await eventually { store.chats.first { $0.id == DemoData.themeChat }?.status == nil })
    #expect(!store.waiting.contains { $0.chatID == DemoData.themeChat })
}

@MainActor
@Test func theDemosHeldTaskCanBeFinishedByPebbleOrAcceptedAsUnverified() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let held = try await task(store, DemoData.themeChat)
    try await store.acceptUnverified(held)
    let transcript = store.transcript(for: DemoData.themeChat)
    #expect(await eventually { transcript.task == nil })
    #expect(!store.waiting.contains { $0.chatID == DemoData.themeChat })
    #expect(
        transcript.items.contains {
            if case .runEnd(_, DemoData.themeRun, .completed, _, let note) = $0 { note == "You accepted this task as unverified." } else { false }
        })
    await #expect(throws: RemoteCallError.self) { try await store.askPebbleToFinish(held) }
    #expect(store.notice?.message == "This task is not waiting on verification.")
}

@MainActor
@Test func askingTheDemoToFinishVerifiesTheChange() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let held = try await task(store, DemoData.themeChat)
    try await store.askPebbleToFinish(held)
    let transcript = store.transcript(for: DemoData.themeChat)
    #expect(await eventually { replies(transcript).last?.text.hasSuffix("The change is verified.") == true })
    #expect(replies(transcript).count == 1)  // the run went on in the same reply
}

@MainActor
@Test func theDemosEditIsUndone() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let transcript = store.transcript(for: DemoData.themeChat)
    _ = await eventually { transcript.items.contains { $0.id == "x/\(DemoData.themeChat)/\(DemoData.themeEdit)" } }
    let edit = try #require(transcript.items.lazy.compactMap { item -> ActionRecord? in
        if case .action(let record) = item { record } else { nil }
    }.first)
    #expect(edit.undo == .edit && edit.title == "Change ThemeToggle.tsx")
    #expect(try await store.undo(edit) == .editUndone)
    #expect(await eventually {
        transcript.items.contains { if case .action(let record) = $0 { record.isUndone && record.undo == nil } else { false } }
    })
}

@MainActor
@Test func theDemosUncertainStepPausesMailUntilItIsSettled() async throws {
    let store = await demoStore()
    let uncertain = try await task(store, DemoData.mailChat)
    #expect(uncertain.needsCheck && !uncertain.hasProject)
    await store.loadPausedWindows(in: DemoData.mailChat)
    let paused = try #require(store.transcript(for: DemoData.mailChat).task?.pausedWindows.first)
    #expect(paused.id == DemoData.mailWindow && paused.appName == "mail")

    // The readback waits while another task runs, without a failure.
    #expect(try await store.readback(uncertain).waitsForTask)
    try await stopTheLoginRun(store)
    let page = try await store.readback(uncertain)
    #expect(page.items.map(\.tool) == ["AppAction", "ScreenAct"])
    #expect(page.items.map(\.canSettleFromReadback) == [true, false])

    try await store.markWindowDone(paused)
    #expect(store.transcript(for: DemoData.mailChat).task?.windowChecked == true)
    try await store.settleFromReadback(page.items[0])
    await #expect(throws: RemoteCallError.self) { try await store.settleFromReadback(page.items[1]) }
    try await store.recordReport(page.items[1], .occurred, note: "It's in Sent.")
    // Nothing uncertain is left: the task is paused, and the run bar offers Resume.
    let transcript = store.transcript(for: DemoData.mailChat)
    #expect(await eventually { transcript.run?.state == .paused })
    #expect(!store.waiting.contains { $0.chatID == DemoData.mailChat })
    try await store.resume(chat: DemoData.mailChat)
    #expect(await eventually { replies(transcript).last?.text.hasSuffix("Done now.") == true })
}

@MainActor
@Test func theDemosRunningCommandTakesAnAnswerAndStops() async throws {
    let store = await demoStore()
    store.watchCommands(in: DemoData.siteChat)
    let transcript = store.transcript(for: DemoData.siteChat)
    #expect(await eventually { transcript.items.contains { $0.id == "p/\(DemoData.siteServer)" } })
    let jobs = transcript.items.compactMap { item -> ProcessJob? in if case .command(let job) = item { job } else { nil } }
    #expect(jobs.map(\.id) == [DemoData.siteServer, DemoData.siteSync])
    let server = jobs[0], sync = jobs[1]

    #expect(store.readsTerminalsQuietly)
    let terminal = try #require(await store.readTerminal(of: server))
    #expect(terminal.takesTyping && !terminal.isSecret)
    #expect(try await store.readOutput(of: server).text.hasSuffix("Open the site in your browser? (y/N) "))
    try await store.typeLine("y", into: server)
    #expect(try await store.readOutput(of: server).text.contains("Opened http://localhost:5173/"))

    await #expect(throws: RemoteCallError.self) { try await store.forgetOutput(of: sync) }
    #expect(store.notice?.message == "Record an inspection before dismissing an uncertain outcome.")
    try await store.recordInspection(of: sync, .effectObserved, note: "The images are in public/.")
    #expect(await eventually {
        transcript.items.contains { if case .command(let job) = $0 { job.id == sync.id && job.inspectionRecorded } else { false } }
    })
    try await store.forgetOutput(of: sync)
    #expect(await eventually { !transcript.items.contains { $0.id == "p/\(DemoData.siteSync)" } })

    try await store.stopCommand(server)
    #expect(await eventually { !transcript.items.contains { $0.id == "p/\(DemoData.siteServer)" } })  // settled, known
}

@MainActor
@Test func theDemosFailedTaskResumesOrContinuesOnTheNewModel() async throws {
    let store = await demoStore()
    let failed = try await task(store, DemoData.deployChat)
    #expect(failed.state == .failed && failed.canResume && failed.showsInConversation)
    try await stopTheLoginRun(store)

    try await store.selectModel("default-local", from: DemoData.deployChat)
    let deploy = store.transcript(for: DemoData.deployChat)
    let offer = HandoffOffer(chatID: DemoData.deployChat, runID: DemoData.deployRun)
    #expect(await eventually { deploy.items.contains(.handoff(offer)) })
    let plan = try await store.previewHandoff(offer)
    #expect(plan.sourceClass == "cloud:chatgpt" && plan.destinationClass == "device" && !plan.uploads)
    #expect(plan.total == 2 && plan.withheld.isEmpty)
    await #expect(throws: RemoteCallError.self) { try await store.startHandoff(plan, for: offer) }
    #expect(store.notice?.message == "The reviewed model handoff was refused (not_approved). Nothing was sent.")
    try await store.approveHandoff(plan, for: offer)
    let chat = try await store.startHandoff(plan, for: offer)
    #expect(chat != DemoData.deployChat)
    #expect(await eventually { store.chats.first { $0.id == chat }?.title == "Handoff: Deploy the preview build" })
    let handedOff = store.transcript(for: chat)
    #expect(await eventually { replies(handedOff).last?.text.hasPrefix("Continuing on the new model.") == true })
    #expect(!deploy.items.contains { if case .handoff = $0 { true } else { false } })
}

@MainActor
@Test func theDemosFailedTaskResumes() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let failed = try await task(store, DemoData.deployChat)
    try await store.resume(failed)
    let transcript = store.transcript(for: DemoData.deployChat)
    #expect(await eventually { replies(transcript).last?.text.hasSuffix("Done now.") == true })
    #expect(await eventually { transcript.task == nil })
}

@MainActor
@Test func theDemoRefusesLimitsOutsidePebblesRange() async throws {
    let store = await demoStore()
    try await stopTheLoginRun(store)
    let limited = TaskAttention(
        chatID: DemoData.deployChat, chatTitle: "Deploy the preview build", runID: DemoData.deployRun, state: .budgetExhausted)
    await #expect(throws: RemoteCallError.self) {
        try await store.resume(limited, limits: RunLimits(maxSteps: 300, maxSeconds: 60))
    }
    #expect(store.notice?.message == "Choose 1\u{2013}256 steps and 1\u{2013}86400 seconds per run.")
}

import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// The real store over the demo's simulated Pebble, end to end. Pace 0: scripts run without waiting.

@MainActor
private func demoStore(autoplay: Bool = false) async -> (RemoteStore, DemoClient) {
    let client = DemoClient(pace: 0, autoplay: autoplay, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats && store.waiting.count == 4 }
    return (store, client)
}

@MainActor
private func replies(_ transcript: Transcript) -> [MessageItem] {
    transcript.items.compactMap { if case .message(let m) = $0, m.role == .assistant { m } else { nil } }
}

@MainActor
private func stopTheLoginRun(_ store: RemoteStore) async throws {
    try await store.stop(chat: DemoData.loginChat)
    #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } })
}

@MainActor
@Test func theDemoOpensWithNineConversationsAndWhatWaits() async throws {
    let (store, _) = await demoStore()
    #expect(store.isDemo)
    #expect(store.connection.phase == .connected && store.connection.route == .demo)
    #expect(store.mac?.name == "MacBook Pro" && store.mac?.batteryPercent == 84)
    #expect(store.pebble?.mode == .auto && store.pebble?.fastReplies == .longTasks && store.pebble?.version == "1.9.28")
    let status = Dictionary(uniqueKeysWithValues: store.chats.map { ($0.id, $0.status) })
    #expect(store.chats.first?.id == DemoData.loginChat)
    #expect(status[DemoData.loginChat] == .thinking)
    #expect(status[DemoData.readmeChat] == .review)
    #expect(status[DemoData.emailsChat] == .question)
    #expect(status[DemoData.commitsChat] == .some(nil))
    #expect(status[DemoData.deployChat] == .error)
    #expect(status[DemoData.themeChat] == .blocked && status[DemoData.mailChat] == .uncertain)
    #expect(status[DemoData.siteChat] == .some(nil))
    #expect(store.chats.first { $0.id == DemoData.readmeChat }?.project == "pebble-docs")
    #expect(Set(store.liveRuns.map(\.id)) == [DemoData.loginRun, DemoData.readmeRun, DemoData.emailsRun])
    // Oldest first: the question (25 minutes ago), the card (6 minutes ago), then the two tasks Pebble holds for a
    // decision: the uncertain step (3 minutes ago) and the held change (2 minutes ago).
    guard case .question(let question) = store.waiting[0], case .review(let card) = store.waiting[1],
        case .task(let uncertain) = store.waiting[2], case .task(let held) = store.waiting[3]
    else {
        Issue.record("expected a question, a card, then two tasks")
        return
    }
    #expect(uncertain.chatID == DemoData.mailChat && uncertain.needsCheck)
    #expect(held.chatID == DemoData.themeChat && held.isHeld && held.hasProject)
    #expect(question.prompts.first?.options.count == 3)
    #expect(card.title == "Run npm test")
    #expect(card.summary == "Runs this command in your project without changing files.")
}

@MainActor
@Test func theDemoStreamsTheLoginFixToTheEnd() async throws {
    let (store, client) = await demoStore(autoplay: true)
    let transcript = store.transcript(for: DemoData.loginChat)
    func loginEnd() -> (state: RunState, seconds: Double?)? {
        for item in transcript.items {
            if case .runEnd(_, let run, let state, let seconds, _) = item, run == DemoData.loginRun { return (state, seconds) }
        }
        return nil
    }
    #expect(await eventually { loginEnd()?.state == .completed })
    #expect(abs((loginEnd()?.seconds ?? 0) - 16.2) < 0.001)  // 2 s before the phone connected, 14.2 s after
    let reply = try #require(replies(transcript).last)
    #expect(reply.text == DemoData.loginReply)
    #expect(!reply.isStreaming)
    func lines() -> [String] {
        transcript.items.compactMap { item -> String? in
            if case .activity(_, _, let text, _) = item { text } else { nil }
        }
    }
    // A read of the conversation can show the run's end before the store has taken the last progress events, which
    // are already on their way: wait for them rather than read the lines at that instant.
    #expect(await eventually { lines().contains("Running the tests (npm test)") })
    #expect(lines().contains("Reading src/auth/session.ts") && lines().contains("Editing src/auth/session.ts"))
    let statuses = transcript.items.compactMap { item -> StatusKey? in
        if case .activity(_, _, _, let status) = item { status } else { nil }
    }
    #expect(Set(statuses) == [.reading, .searching, .editing, .testing])
    let tokens = await client.sent.filter { $0.name == "token" }
    #expect(tokens.count > 20)  // streamed piece by piece
    #expect(await eventually { store.banner?.title == "Pebble finished" })
    #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } })
    #expect(await eventually { store.chats.first { $0.id == DemoData.loginChat }?.status == nil })
}

@MainActor
@Test func theDemoRefusesASecondTaskThenRunsTheNextMessage() async throws {
    let (store, _) = await demoStore()
    let transcript = store.transcript(for: DemoData.weatherChat)
    #expect(await eventually { replies(transcript).count == 1 })
    await #expect(throws: RemoteCallError.self) { try await store.send("Will it rain on Monday?", in: DemoData.weatherChat) }
    #expect(store.notice?.message == "One task can run at a time on this device.")
    try await stopTheLoginRun(store)
    try await store.send("Will it rain on Monday?", in: DemoData.weatherChat)
    #expect(await eventually { replies(transcript).count == 2 && replies(transcript).last?.isStreaming == false })
    #expect(replies(transcript).last?.text.hasPrefix("This is the demo, so there's no Mac behind me.") == true)
    #expect(transcript.items.contains { if case .runEnd(_, _, .completed, _, _) = $0 { true } else { false } })
    #expect(await eventually { transcript.run == nil })
}

@MainActor
@Test func approvingTheDemoCardRunsTheTestsAndFinishesTheReadme() async throws {
    let (store, _) = await demoStore()
    let transcript = store.transcript(for: DemoData.readmeChat)
    let card = try #require(store.waiting.lazy.compactMap { if case .review(let card) = $0 { card } else { nil } }.first)
    await #expect(throws: RemoteCallError.self) { try await store.approve(card) }
    #expect(store.notice?.message == "Wait for the current task to finish before approving an action.")
    try await stopTheLoginRun(store)
    try await store.approve(card)
    #expect(await eventually { store.waiting.count == 3 })  // the question and the two held tasks
    #expect(
        await eventually {
            replies(transcript).last?.text.hasSuffix("The README is ready for 2.0.") == true && replies(transcript).last?.isStreaming == false
        })
    #expect(replies(transcript).count == 1)  // the run went on in the same reply
    #expect(await eventually { !store.liveRuns.contains { $0.id == DemoData.readmeRun } })
    #expect(store.chats.first { $0.id == DemoData.readmeChat }?.status == nil)
}

@MainActor
@Test func answeringTheDemoQuestionDraftsTheEmails() async throws {
    let (store, _) = await demoStore()
    let transcript = store.transcript(for: DemoData.emailsChat)
    try await stopTheLoginRun(store)
    guard case .question(let question) = try #require(store.waiting.first) else { return }
    try await store.answer(question, with: ["tone": .option(id: "warm", text: nil)])
    #expect(await eventually { store.waiting.count == 3 })  // the card and the two held tasks
    #expect(await eventually { transcript.items.contains { $0.id == "m/answer-\(DemoData.emailsQuestion)" } })
    #expect(
        await eventually {
            replies(transcript).last?.text.contains("in a warm and friendly tone") == true && replies(transcript).last?.isStreaming == false
        })
    // The run ends just after its reply's last words: wait for it, as the README test does.
    #expect(await eventually { store.chats.first { $0.id == DemoData.emailsChat }?.status == nil })
}

@MainActor
@Test func theDemosSettingsReactAsPebblesDo() async throws {
    let (store, _) = await demoStore()
    await #expect(throws: RemoteCallError.self) { try await store.setPermissionMode(.full) }
    #expect(store.notice?.message == "Stop the task before changing permissions.")
    try await stopTheLoginRun(store)
    try await store.setPermissionMode(.full)
    #expect(await eventually { store.pebble?.mode == .full })
    try await store.setFastReplies(.off)
    #expect(await eventually { store.pebble?.fastReplies == .off })
    try await store.setStealth(true)
    #expect(await eventually { store.pebble?.stealth == true })
    try await store.setKeepAwake(false)
    #expect(store.mac?.keepAwake == false)
}

@MainActor
@Test func theDemosFailedRunShowsOnlyTheSentenceForThePerson() async throws {
    let (store, _) = await demoStore()
    let transcript = store.transcript(for: DemoData.deployChat)
    #expect(
        await eventually {
            transcript.items.dropLast().last
                == .runEnd(
                    id: "end-\(DemoData.deployRun)", runID: DemoData.deployRun, state: .failed, seconds: 14.6,
                    note: "The preview server didn't start: port 4173 is already in use.")
        })
    // Under it, Pebble's line for the failed task, which can resume (lane R).
    #expect(transcript.items.last?.id == "t/\(DemoData.deployChat)/\(DemoData.deployRun)")
}

@MainActor
@Test func theDemoKeepsWhatHappenedWhileAwayAndResumes() async throws {
    let (store, client) = await demoStore()
    store.stop()
    #expect(await eventually { store.connection.phase == .idle })
    // Pebble goes on while the phone is away.
    await client.disconnect()
    store.start()
    #expect(await eventually { store.connection.phase == .connected && store.bridge?.resumed == true })
    try await stopTheLoginRun(store)
}

@MainActor
@Test func theDemoTakesAPictureOfItsScreen() async throws {
    let (store, _) = await demoStore()
    let picture = try await store.screenshot()
    let display = try #require(picture.displays.first)
    #expect(display.width == 1280 && display.height == 832 && display.format == "jpeg")
    #expect(display.data.prefix(2) == Data([0xFF, 0xD8]))  // a JPEG
    #expect(display.data.count > 2_000)
    #expect(picture.takenAt == Fixture.t0)
    await #expect(throws: RemoteCallError.self) { _ = try await store.screenshot(display: 3) }
}

import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// The Control tab's flows end to end: the real store over the demo's simulated Pebble (pace 0, clock fixed).

@MainActor
private func demo() async -> RemoteStore {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.clock = { Fixture.t0 }
    store.start()
    _ = await eventually { store.pebble != nil && store.chats.count == DemoData.seededChats }
    try? await store.stop(chat: DemoData.loginChat)  // the scripted run would hold Pebble's one worker
    _ = await eventually { !store.liveRuns.contains { $0.id == DemoData.loginRun } }
    return store
}

@MainActor
@Test func theDemosSchedulesPauseResumeAndAreMade() async throws {
    let store = await demo()
    await store.loadControlLists()
    #expect(store.schedules.map(\.name) == ["Weekly commit summary", "Lisbon weather each morning"])
    #expect(store.jobNotices.first?.title == "Scheduled job \u{201C}Weekly commit summary\u{201D} completed")
    let weekly = store.schedules[0]
    #expect(weekly.schedule == .daily(time: "09:00", timezone: "Europe/Lisbon") && weekly.chatTitle == "Summarize this week's commits")
    try await store.pauseSchedule(weekly)
    #expect(store.schedules.first { $0.id == weekly.id }?.isPaused == true)
    let paused = try #require(store.schedules.first { $0.id == weekly.id })
    try await store.resumeSchedule(paused, review: try await store.reviewResume(paused))
    #expect(store.schedules.first { $0.id == weekly.id }?.state == "active")
    // A stale revision is refused in Pebble's words.
    await #expect(throws: RemoteCallError.self) { try await store.pauseSchedule(weekly) }
    #expect(store.notice?.message == "This job changed since you reviewed it. Reload it and try again.")
    // A new one: preview, then create.
    let review = try await store.previewSchedule(in: DemoData.weatherChat, schedule: .interval(seconds: 7200))
    #expect(review.nextTimes.count == 5 && review.nextTimes.first == Fixture.at(7200))
    let made = try await store.createSchedule(
        in: DemoData.weatherChat, name: "Rain check", task: "Will it rain today?", schedule: .interval(seconds: 7200), review: review)
    #expect(store.schedules.contains { $0.id == made.id && $0.nextRun == Fixture.at(7200) })
    try await store.deleteSchedule(made)
    #expect(!store.schedules.contains { $0.id == made.id })
    try await store.acknowledge(try #require(store.jobNotices.first))
    #expect(store.jobNotices.isEmpty)
}

@MainActor
@Test func theDemosToolboxKeepsRemovesAndPutsBack() async throws {
    let store = await demo()
    await store.load(.toolbox)
    #expect(store.toolbox.map(\.name) == ["c_to_f", "word_count"])
    #expect(store.toolboxDecisions.first?.name == "split_bill")
    try await store.decide(store.toolboxDecisions[0], keep: true)
    #expect(store.toolbox.map(\.name).contains("split_bill") && store.toolboxDecisions.isEmpty)
    let tool = try #require(store.toolbox.first { $0.name == "c_to_f" })
    #expect(try await store.toolDetail(named: tool.name).code.contains("* 9 / 5 + 32"))
    try await store.removeTool(tool)
    #expect(store.removedTools.first?.name == "c_to_f" && store.removedTools.first?.secondsLeft == 600)
    try await store.putBack(store.removedTools[0])
    #expect(store.toolbox.contains { $0.name == "c_to_f" } && store.removedTools.isEmpty)
}

@MainActor
@Test func theDemosScreenSessionsEndAndComeBack() async throws {
    let store = await demo()
    await store.load(.screenSessions)
    // The Mail window an uncertain step paused is listed too (lane R's demo).
    #expect(Set(store.screenSessions.map(\.id)) == ["session-notes", "session-docs", DemoData.mailWindow])
    let docs = try #require(store.screenSessions.first { $0.id == "session-docs" })
    #expect(docs.kind == "browser" && docs.state == "handoff" && docs.reasons == ["login_form"])
    try await store.markScreenSessionDone(docs)
    #expect(await eventually { store.screenSessions.first { $0.id == "session-docs" }?.state == "active" })
    try await store.revokeScreenSession(try #require(store.screenSessions.first { $0.id == "session-notes" }))
    await store.load(.screenSessions)
    #expect(store.screenSessions.map(\.id) == ["session-docs", DemoData.mailWindow])
}

@MainActor
@Test func theDemosRecentlyDeletedRestoresAndDeletesForGood() async throws {
    let store = await demo()
    try await store.trash(chat: DemoData.weatherChat)
    #expect(await eventually { !store.chats.contains { $0.id == DemoData.weatherChat } })
    await store.load(.trash)
    let item = try #require(store.trashed.first)
    #expect(item.title == "Weather in Lisbon this weekend" && item.deleteAfter == Fixture.at(2_592_000))
    await #expect(throws: RemoteCallError.self) { try await store.send("Still there?", in: DemoData.weatherChat) }
    #expect(store.notice?.code == "trashed_conversation")
    try await store.restore(item)
    #expect(await eventually { store.chats.contains { $0.id == DemoData.weatherChat } })
    try await store.trash(chat: DemoData.weatherChat)
    await store.load(.trash)
    try await store.purge(try #require(store.trashed.first))
    #expect(await eventually { !store.chats.contains { $0.id == DemoData.weatherChat } })
    await store.load(.trash)
    #expect(store.trashed.isEmpty)
}

@MainActor
@Test func theDemoTakesAPhotoWithTheNextTask() async throws {
    let store = await demo()
    let transcript = store.transcript(for: DemoData.weatherChat)
    #expect(await eventually { !transcript.items.isEmpty })
    var photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
    photo.append(Data(repeating: 3, count: 150_000))
    let attached = try await store.attach(photo, name: "IMG_0042.JPG", to: DemoData.weatherChat)
    #expect(attached.kind == "image" && attached.bytes == 150_004)
    try await store.send("What's the weather like in this photo?", in: DemoData.weatherChat)
    #expect(store.attachments[DemoData.weatherChat] == nil)
    #expect(
        await eventually {
            transcript.items.contains { item in
                if case .message(let message) = item { message.attachments.first?.id == attached.id } else { false }
            }
        })
}

@MainActor
@Test func theDemosRunDetailsTellWhatPebbleDid() async throws {
    let store = await demo()
    let details = try await store.runDetails(DemoData.deployRun, in: DemoData.deployChat)
    #expect(details.run.state == .failed && details.run.note == "The preview server didn't start: port 4173 is already in use.")
    #expect(details.items.map(\.label) == ["Reading package.json", "Starting the preview (npm run preview)"])
    #expect(details.items.last?.status == "failed")
}

@MainActor
@Test func theDemosModelsAndSettingsReactAsPebblesDo() async throws {
    let store = await demo()
    await store.load(.models)
    #expect(store.models.map(\.name) == ["GPT-5.1", "Qwen 3.5 9B"])
    #expect(store.models.last?.efforts == ["quick", "think"] && store.models.last?.isLocal == true)
    try await store.selectModel("default-local")
    #expect(await eventually { store.currentModelID == "default-local" })
    try await store.setEffort("quick")
    #expect(await eventually { store.pebble?.effort == "quick" })
    await #expect(throws: RemoteCallError.self) { try await store.setEffort("high") }
    #expect(store.notice?.message == "This model does not support that effort level. Choose one of its available settings.")
    await #expect(throws: RemoteCallError.self) { try await store.setCompanion(["pointer": true]) }
    #expect(store.notice?.message == "Supply exactly pointer, reactions, status_words and ui_guidance for the companion.")
    try await store.setGitDecisions(["force_push": false, "delete_remote_branch": true, "repository_identity": true, "clean": true])
    #expect(await eventually { store.settings?.gitDecisions["force_push"] == false })
    try await store.setMemoryLayer("episodic", on: false)
    #expect(await eventually { store.settings?.memoryLayers["episodic"] == false })
    var notifications = try #require(await { () async -> JSONValue? in
        await store.load(.notifications)
        return store.notificationSettings
    }())
    if case .object(var object) = notifications {
        object["enabled"] = true
        notifications = .object(object)
    }
    try await store.setNotifications(notifications)
    await store.load(.notifications)
    #expect(store.notificationSettings?["enabled"] == true)
}

@MainActor
@Test func theDemoStartsLockedAndUnlocksForItsFirstAction() async throws {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.clock = { Fixture.t0 }
    store.start()
    #expect(await eventually { store.pebble != nil })
    #expect(store.unlockedUntil == nil && store.bridge?.unlockSeconds == 900)  // reads need no unlock
    try await store.setStealth(true)  // an action: the demo's Face ID agrees, as the live client asks it
    #expect(await eventually { store.unlockedUntil == Fixture.at(900) })
    #expect(store.isUnlocked)
}

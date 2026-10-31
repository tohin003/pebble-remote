import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Schedules, Toolbox, screen sessions, Recently deleted, photos and run details against a FakeClient: Pebble's exact
// params (its lambda routes refuse any other), which calls ask for Face ID, and what the screens then read.

/// Pebble's `state`, which a test may change.
private final class StateAnswer: Sendable {
    private let value: Mutex<JSONValue>
    init(_ value: JSONValue = Fixture.stateJSON()) { self.value = Mutex(value) }
    var current: JSONValue {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

@MainActor
private func workflowStore(
    state: StateAnswer = StateAnswer(),
    extra: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try extra(method, params) { return answer }
        switch method {
        case "state": return state.current
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        default: return .bool(true)
        }
    }
    let store = RemoteStore(client: fake)
    store.clock = { Fixture.at(60) }
    fake.push(.welcome(.test(methods: DemoClient.methods)))
    _ = await eventually { store.pebble != nil }
    return (store, fake)
}

private func job(_ id: String, state: String = "active", revision: Int = 3, next: Double? = 3600) -> JSONValue {
    [
        "id": .string(id), "name": "Weekly commit summary", "task": "Summarize this week's commits.",
        "schedule": ["kind": "daily", "time": "09:00", "timezone": "Europe/Lisbon"], "state": .string(state),
        "revision": .int(revision), "next_fire": next.map { .double(Fixture.t0.timeIntervalSince1970 + $0) } ?? .null,
        "error": .null, "last_run_id": .null, "last_run_state": "completed", "monitor": false, "config": [:],
    ]
}

@MainActor
@Test func schedulesComeFromEveryConversationWithAJob() async throws {
    let (store, fake) = await workflowStore { method, params in
        switch method {
        case "notification_status":
            return [
                "settings": ["enabled": false, "kinds": [:], "preview": "title", "quiet_hours": .null, "replies": true],
                "jobs": [["job_id": "j1", "chat_id": "c1", "label": "Weekly", "state": "active", "muted": false]],
            ]
        case "job_list":
            return params["id"] == "c1" ? ["jobs": [job("j1"), job("j2", state: "paused", next: nil)], "notifications": []] : nil
        case "job_pause": return job("j1", state: "paused", revision: 4, next: nil)
        default: return nil
        }
    }
    await store.loadControlLists()
    #expect(store.schedules.map(\.id) == ["j1", "j2"])  // soonest first, paused last
    let weekly = try #require(store.schedules.first)
    #expect(weekly.schedule == .daily(time: "09:00", timezone: "Europe/Lisbon"))
    #expect(weekly.nextRun == Fixture.at(3600) && weekly.chatTitle == "Fix the login redirect loop")
    #expect(store.schedules.last?.isPaused == true)
    #expect(store.notificationSettings?["preview"] == "title")
    try await store.pauseSchedule(weekly)
    let call = try #require(fake.calls("job_pause").last)
    #expect(call.params == ["id": "c1", "job_id": "j1", "revision": 3] && !call.elevated)
    #expect(store.schedules.first { $0.id == "j1" }?.isPaused == true)
}

@MainActor
@Test func resumingOrMakingAScheduleNeedsItsReviewAndFaceID() async throws {
    let (store, fake) = await workflowStore { method, _ in
        switch method {
        case "job_preview_resume": return ["config_fingerprint": "f1", "config": ["effort": "medium"]]
        case "job_resume": return job("j2", revision: 6)
        case "job_preview":
            return ["config_fingerprint": "f2", "config": ["workspace": .null], "next_times": [1_761_762_600, 1_761_766_200]]
        case "job_create": return job("j3", revision: 1)
        default: return nil
        }
    }
    let paused = ScheduleItem(id: "j2", chatID: "c1", chatTitle: "x", name: "Weekly commit summary", state: "paused", revision: 4)
    let review = try await store.reviewResume(paused)
    #expect(fake.calls("job_preview_resume").last?.params == ["id": "c1", "job_id": "j2", "revision": 4])
    try await store.resumeSchedule(paused, review: review)
    let resume = try #require(fake.calls("job_resume").last)
    #expect(resume.elevated && resume.reason == "Resume the schedule \u{201C}Weekly commit summary\u{201D}")
    #expect(resume.params == ["id": "c1", "job_id": "j2", "revision": 4, "config_fingerprint": "f1"])

    let preview = try await store.previewSchedule(
        in: "c1", schedule: .interval(seconds: 3600), catchUp: .skipIfLate(graceSeconds: 600))
    #expect(
        fake.calls("job_preview").last?.params
            == [
                "id": "c1", "limits": .null,
                "schedule": ["kind": "interval", "seconds": 3600, "catch_up": "skip_if_late", "grace_seconds": 600],
            ])
    #expect(preview.nextTimes == [Date(timeIntervalSince1970: 1_761_762_600), Date(timeIntervalSince1970: 1_761_766_200)])
    let made = try await store.createSchedule(
        in: "c1", name: "Hourly check", task: "Check the build.", schedule: .interval(seconds: 3600),
        catchUp: .skipIfLate(graceSeconds: 600), review: preview)
    let create = try #require(fake.calls("job_create").last)
    #expect(create.elevated && create.reason == "Create the schedule \u{201C}Hourly check\u{201D}")
    #expect(Set(create.params.object?.keys ?? [:].keys) == ["id", "name", "task", "schedule", "monitor", "limits", "config_fingerprint"])
    #expect(create.params["config_fingerprint"] == "f2" && create.params["monitor"] == false)
    #expect(made.id == "j3" && store.schedules.contains { $0.id == "j3" })
}

@MainActor
@Test func toolboxCallsSendExactlyTheirParams() async throws {
    let listing: JSONValue = [
        "tools": [["name": "c_to_f", "purpose": "Converts", "kept_by": "pebble", "kept_at": 1_761_700_000.5, "uses": 3, "last_used": .null, "state": "ok"]],
        "pending": [["id": "p1", "name": "split_bill", "purpose": "Splits", "why": ["it has not been used successfully in this task yet"], "chat_id": "c1"]],
        "removed": [["name": "old", "purpose": "Gone", "seconds_left": 420]],
    ]
    let (store, fake) = await workflowStore { method, _ in method.hasPrefix("toolbox_") && method != "toolbox_get" ? listing : JSONValue?.none }
    await store.load(.toolbox)
    #expect(store.toolbox.first?.keptByPebble == true && store.toolbox.first?.uses == 3)
    #expect(store.toolboxDecisions.first?.why == ["it has not been used successfully in this task yet"])
    #expect(store.removedTools.first?.secondsLeft == 420)
    try await store.removeTool(store.toolbox[0])
    #expect(fake.calls("toolbox_remove").last?.params == ["name": "c_to_f"])
    try await store.putBack(store.removedTools[0])
    #expect(fake.calls("toolbox_undo_remove").last?.params == ["name": "old"])
    try await store.decide(store.toolboxDecisions[0], keep: true)
    #expect(fake.calls("toolbox_decide").last?.params == ["pending_id": "p1", "keep": true])
    #expect(fake.calls("toolbox_list").last?.params == [:])
}

@MainActor
@Test func screenSessionsListOnlyLiveOnesAndEndWithTheirId() async throws {
    let state = Fixture.stateJSON(chats: [Fixture.chatRow("c1", "a", updated: 30), Fixture.chatRow("c2", "b", updated: -86_400)])
    let (store, fake) = await workflowStore(state: StateAnswer(state)) { method, params in
        guard method == "screen_sessions" else { return nil }
        guard params == ["id": "c1"] else { return [] }
        return [
            ["session_id": "s1", "run_id": "r1", "kind": "app", "target": ["kind": "app", "bundle_id": "com.apple.calculator"],
             "actions": ["press"], "state": "active", "reason": .null, "expires": .double(Fixture.t0.timeIntervalSince1970 + 600), "pending": false],
            ["session_id": "s2", "kind": "browser", "target": ["kind": "browser", "profile": "chrome", "origins": ["https://a.example"]],
             "actions": [], "state": "active", "expires": .double(Fixture.t0.timeIntervalSince1970 - 5), "pending": false],
            ["session_id": "s3", "kind": "app", "target": ["kind": "app"], "actions": [], "state": "revoked",
             "expires": .double(Fixture.t0.timeIntervalSince1970 + 600), "pending": false],
        ]
    }
    await store.load(.screenSessions)
    #expect(fake.calls("screen_sessions").map(\.params) == [["id": "c1"]])  // only a conversation active lately
    #expect(store.screenSessions.map(\.id) == ["s1"])  // past its time or ended: not shown
    #expect(store.screenSessions.first?.appName == "calculator")
    try await store.revokeScreenSession(store.screenSessions[0])
    #expect(fake.calls("screen_session_revoke").last?.params == ["session_id": "s1"])
    #expect(store.screenSessions.isEmpty)
}

@MainActor
@Test func recentlyDeletedAndDeletingForGoodWithFaceID() async throws {
    let state = StateAnswer()
    let (store, fake) = await workflowStore(state: state) { method, _ in
        switch method {
        case "storage_trash_chat":
            state.current = Fixture.stateJSON(chats: [])
            return ["trashed": "c1", "delete_after": 1_764_351_000]
        case "storage_summary":
            return ["recently_deleted": [["chat_id": "c1", "title": "Fix the login redirect loop", "deleted": 1_761_759_000, "origin": "app", "delete_after": 1_764_351_000]]]
        case "storage_purge_chat": return ["deleted": "c1"]
        default: return nil
        }
    }
    _ = store.transcript(for: "c1")
    #expect(await eventually { store.transcript(for: "c1").items.isEmpty && store.chats.count == 1 })
    try await store.trash(chat: "c1")
    #expect(fake.calls("storage_trash_chat").last?.params == ["chat_id": "c1"])
    #expect(await eventually { store.chats.isEmpty })  // gone from the list, open or not
    await store.load(.trash)
    let item = try #require(store.trashed.first)
    #expect(item.deleteAfter == Date(timeIntervalSince1970: 1_764_351_000))
    try await store.purge(item)
    let purge = try #require(fake.calls("storage_purge_chat").last)
    #expect(purge.elevated && purge.params == ["chat_id": "c1", "confirm": true])
    #expect(purge.reason == "Delete \u{201C}Fix the login redirect loop\u{201D} for good")
    #expect(store.trashed.isEmpty)
}

@MainActor
@Test func aPhotoGoesInPebblesPiecesAndOnlyWithANewTask() async throws {
    let (store, fake) = await workflowStore { method, params in
        switch method {
        case "attach_bytes":
            if params["final"] == true {
                return ["id": "src1", "name": "IMG_0001.JPG", "kind": "image", "preview": "data:image/jpeg;base64,/9j/", "characters": 0, "bytes": 150_000]
            }
            return ["upload": "u1", "received": .int((params["offset"]?.int ?? 0) + 72_000)]
        case "send": return ["message_id": "m3", "run_id": "r3"]
        default: return nil
        }
    }
    var photo = Data([0xFF, 0xD8])
    photo.append(Data(repeating: 7, count: 149_998))
    let attached = try await store.attach(photo, name: "IMG_0001.JPG", to: "c1")
    let pieces = fake.calls("attach_bytes")
    #expect(pieces.map { $0.params["offset"]?.int } == [0, 72_000, 144_000])
    #expect(pieces.map { $0.params["final"]?.bool } == [false, false, true])
    #expect(pieces.map { $0.params["upload"]?.string } == [nil, "u1", "u1"])
    #expect(pieces.map { $0.params["data_base64"]?.string?.count } == [96_000, 96_000, 8_000])
    #expect(attached.kind == "image" && attached.preview == Data([0xFF, 0xD8, 0xFF]))
    #expect(store.attachments["c1"] == [attached])
    try await store.send("What's in this photo?", in: "c1")
    #expect(fake.calls("send").last?.params["source_ids"] == ["src1"])
    #expect(store.attachments["c1"] == nil)  // Pebble took it with the message
    try await store.removeAttachment(attached, from: "c1")
    #expect(fake.calls("remove_source").last?.params == ["id": "c1", "source_id": "src1"])
}

@MainActor
@Test func runDetailsReadTheRowAndActivityButNeverRunGet() async throws {
    let (store, fake) = await workflowStore { method, _ in
        switch method {
        case "run_list":
            return [Fixture.runRow("r1", chat: "c1", state: "failed", elapsed: 14.6, error: "Port 4173 is in use. Do not claim it is live.", steps: 3)]
        case "run_activity":
            return [
                "run_id": "r1", "state": "failed", "started": 1_761_759_000, "elapsed": 14.6,
                "items": [
                    ["seq": 128, "at": 1.0, "kind": "tool", "label": "Starting the preview", "detail": "Port 4173 is in use.", "duration": 12.4, "status": "failed"],
                    ["seq": 64, "at": 0.3, "kind": "tool", "label": "Reading package.json", "detail": .null, "duration": 0.5, "status": "done"],
                ],
                "reasoning": ["available": true, "text": "The port is taken."], "usage": .null, "next": 128,
            ]
        default: return nil
        }
    }
    let details = try await store.runDetails("r1", in: "c1")
    #expect(fake.calls("run_activity").last?.params == ["run_id": "r1", "after": 0])
    #expect(fake.calls("run_get").isEmpty)
    #expect(details.items.map(\.label) == ["Reading package.json", "Starting the preview"])
    #expect(details.items.last?.status == "failed" && details.items.last?.detail == "Port 4173 is in use.")
    #expect(details.run.note == "Port 4173 is in use." && details.run.steps == 3)
    #expect(details.reasoning == "The port is taken.")
}

@MainActor
@Test func listsReadAgainOnTheirEventsOnlyOnceAScreenReadThem() async throws {
    let (store, fake) = await workflowStore { method, _ in
        method == "toolbox_list" ? ["tools": [], "pending": [], "removed": []] : nil
    }
    fake.push("toolbox", ["chat_id": "c1", "run_id": "r1", "kind": "kept", "name": "c_to_f"])
    try await Task.sleep(for: .milliseconds(50))
    #expect(fake.calls("toolbox_list").isEmpty)
    await store.load(.toolbox)
    #expect(fake.calls("toolbox_list").count == 1)
    fake.push("toolbox", ["chat_id": "c1", "run_id": "r1", "kind": "kept", "name": "word_count"])
    #expect(await eventually { fake.calls("toolbox_list").count == 2 })
}

@MainActor
@Test func everySettingKeyTakesItsWholeValue() async throws {
    let (store, fake) = await workflowStore()
    let companion: JSONValue = ["pointer": true, "reactions": false, "status_words": "fixed", "ui_guidance": true]
    try await store.setCompanion(companion)
    #expect(fake.calls("setting").last?.params == ["key": "companion", "value": companion])
    let git: JSONValue = ["force_push": false, "delete_remote_branch": true, "repository_identity": true, "clean": true]
    try await store.setGitDecisions(git)
    #expect(fake.calls("setting").last?.params == ["key": "git_decisions", "value": git])
    try await store.setReducedMotion(true)
    try await store.setMemoryEnabled(false)
    #expect(fake.calls("setting").suffix(2).map { $0.params["key"] } == ["reduced_motion", "memory_enabled"])
    #expect(fake.calls("setting").allSatisfy { !$0.elevated })
}

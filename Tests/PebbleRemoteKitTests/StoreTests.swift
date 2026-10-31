import Foundation
import PebbleProtocol
import Testing

@testable import PebbleRemoteKit

// RemoteStore against a FakeClient: what it calls, with which params, and what the screens then read.

@MainActor
private func connectedStore(
    state: JSONValue = Fixture.stateJSON(),
    chat: JSONValue = Fixture.chatDetail(),
    bridge: BridgeInfo = .test(),
    macStore: (any PairedMacStore)? = nil,
    extra: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try extra(method, params) { return answer }
        switch method {
        case "state": return state
        case "get_chat", "remote.chat_tail": return chat
        case "remote.status":
            return [
                "mac": ["name": "Studio Mac", "battery_percent": 90, "charging": false, "on_power": true, "keep_awake": false],
                "pebble": ["running": true, "version": "1.9.28"], "bridge": ["version": "0.1", "epoch": "e1", "endpoints": []],
            ]
        default: return .bool(true)
        }
    }
    let store = RemoteStore(client: fake, macStore: macStore)
    fake.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
    fake.push(.welcome(bridge))
    _ = await eventually { store.pebble != nil && store.mac?.batteryPercent != nil }
    return (store, fake)
}

private let liveState = Fixture.stateJSON(
    runs: [Fixture.runRow("r1", chat: "c1", state: "running")], active: "c1", activeRun: "r1")

@MainActor
@Test func connectingReadsStateAndTheMac() async throws {
    let (store, fake) = await connectedStore()
    #expect(store.connection.phase == .connected)
    #expect(store.bridge?.macName == "Studio Mac")
    #expect(store.pebble?.mode == .ask)
    #expect(store.mac?.name == "Studio Mac" && store.mac?.batteryPercent == 90 && store.mac?.keepAwake == false)
    #expect(store.chats.map(\.title) == ["Fix the login redirect loop"])
    #expect(fake.methods.prefix(2) == ["state", "remote.status"])
}

@MainActor
@Test func aMessageWhileARunWorksReachesThatRunThroughSend() async throws {
    let (store, fake) = await connectedStore(state: liveState) { method, _ in
        method == "send" ? ["message_id": "m7", "input_id": "i1", "run_id": "r1", "status": "queued", "steering": true] : nil
    }
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading && transcript.sendsGuidance })
    #expect(store.sendsGuidance(in: "c1"))
    try await store.send("  Also update the README  ", in: "c1")
    let sent = try #require(fake.calls("send").last)
    #expect(sent.params == ["id": "c1", "text": "Also update the README"])  // no sources, no new run
    #expect(!sent.elevated)
    #expect(fake.calls("run_steer").isEmpty)
    #expect(transcript.items.contains { $0.id == "m/m7" })
}

@MainActor
@Test func aMessageWithNothingWorkingStartsARun() async throws {
    let (store, fake) = await connectedStore { method, _ in
        method == "send" ? ["message_id": "m3", "run_id": "r9"] : nil
    }
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading })
    #expect(!transcript.sendsGuidance)
    try await store.send("Fix the redirect loop", in: "c1")
    #expect(fake.calls("send").last?.params == ["id": "c1", "text": "Fix the redirect loop"])
    #expect(transcript.items.last?.id == "m/m3")
    // A first message names the conversation and no event says so: state is read again.
    #expect(await eventually { fake.calls("state").count >= 2 })
}

@MainActor
@Test func aRefusedMessageShowsPebblesWordsAndLeavesTheConversation() async throws {
    let refusal = PersonFacingError(message: "One task can run at a time on this device.")
    let (store, _) = await connectedStore { method, _ in
        if method == "send" { throw RemoteCallError.refused(refusal) }
        return nil
    }
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading })
    await #expect(throws: RemoteCallError.refused(refusal)) { try await store.send("Another task", in: "c1") }
    #expect(store.notice?.message == "One task can run at a time on this device.")
    #expect(!transcript.items.contains { if case .message(let m) = $0 { m.text == "Another task" } else { false } })
}

@MainActor
@Test func approvingAsksForFaceIDWithTheCardsTitle() async throws {
    let (store, fake) = await connectedStore(chat: Fixture.chatDetail(actions: [Fixture.action("a2")]))
    _ = store.transcript(for: "c1")
    #expect(await eventually { !store.waiting.isEmpty })
    guard case .review(let item) = try #require(store.waiting.first) else {
        Issue.record("expected a card")
        return
    }
    try await store.approve(item)
    let call = try #require(fake.calls("approve").last)
    #expect(call.elevated)
    #expect(call.params == ["id": "c1", "action_id": "a2"])
    #expect(call.reason == "Approve: Run npm test")
}

@MainActor
@Test func approvingUsesApproveSimpleOnlyWhenTheBridgeLacksApprove() async throws {
    var methods = BridgeInfo.test().methods
    methods.remove("approve")
    methods.remove("reject")
    let grant = Fixture.action("a3", kind: "browser_grant", payload: ["sites": ["https://www.youtube.com/"], "route": "tab"])
    let (store, fake) = await connectedStore(chat: Fixture.chatDetail(actions: [grant]), bridge: .test(methods: methods))
    _ = store.transcript(for: "c1")
    #expect(await eventually { !store.waiting.isEmpty })
    guard case .review(let item) = try #require(store.waiting.first) else { return }
    #expect(item.title == "Use youtube.com")
    try await store.approve(item)
    #expect(fake.calls("approve_simple").last?.elevated == true)
    try await store.reject(item)
    #expect(fake.calls("reject_simple").last?.params == ["id": "c1", "action_id": "a3"])
}

@MainActor
@Test func cancellingFaceIDIsNotAFailureToShow() async throws {
    let (store, _) = await connectedStore(chat: Fixture.chatDetail(actions: [Fixture.action("a2")])) { method, _ in
        if method == "approve" { throw RemoteCallError.cancelledByPerson }
        return nil
    }
    _ = store.transcript(for: "c1")
    #expect(await eventually { !store.waiting.isEmpty })
    guard case .review(let item) = try #require(store.waiting.first) else { return }
    await #expect(throws: RemoteCallError.cancelledByPerson) { try await store.approve(item) }
    #expect(store.notice == nil)
}

@MainActor
@Test func aResyncReadsStateAndTheOpenConversationsAgain() async throws {
    let (store, fake) = await connectedStore()
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading })
    let states = fake.calls("state").count
    let tails = fake.calls("remote.chat_tail").count
    fake.push(.resyncNeeded)
    #expect(await eventually { fake.calls("state").count > states && fake.calls("remote.chat_tail").count > tails })
}

@MainActor
@Test func aWelcomeThatDidNotResumeReadsEverythingAgain() async throws {
    let (store, fake) = await connectedStore()
    defer { withExtendedLifetime(store) {} }
    let states = fake.calls("state").count
    fake.push(.welcome(.test(resumed: true)))
    try await Task.sleep(for: .milliseconds(50))
    #expect(fake.calls("state").count == states)  // resumed: the missed events were replayed
    fake.push(.welcome(.test(resumed: false)))
    #expect(await eventually { fake.calls("state").count > states })
}

@MainActor
@Test func conversationsReadTheWholeChatWhenTheBridgeHasNoTail() async throws {
    var methods = BridgeInfo.test().methods
    methods.remove("remote.chat_tail")
    let (store, fake) = await connectedStore(
        chat: Fixture.chatDetail(messages: [Fixture.message("m1", "user", "Hi")]), bridge: .test(methods: methods))
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { transcript.items.count == 1 })
    #expect(fake.calls("get_chat").last?.params == ["id": "c1"])
    #expect(fake.calls("remote.chat_tail").isEmpty)
    #expect(transcript.title == "Fix the login redirect loop")
    #expect(transcript.project == "pebble-web")
}

@MainActor
@Test func thePermissionModeChangeSendsPebbleTheWholeObjectWithFaceID() async throws {
    let (store, fake) = await connectedStore()
    try await store.setPermissionMode(.full)
    let call = try #require(fake.calls("setting").last)
    #expect(call.elevated)
    #expect(call.reason == "Change Pebble's permissions")
    #expect(call.params["key"] == "permissions")
    var expected = Fixture.permissions
    if case .object(var object) = expected {
        object["mode"] = "full"
        expected = .object(object)
    }
    #expect(call.params["value"] == expected)  // every tool group as it was: Pebble refuses partial objects
}

@MainActor
@Test func fastRepliesStealthAndKeepAwakeAreSettings() async throws {
    let (store, fake) = await connectedStore { method, params in
        method == "remote.keep_awake" ? ["keep_awake": params["on"] ?? false] : nil
    }
    try await store.setFastReplies(.always)
    #expect(fake.calls("setting").last?.params == ["key": "fast_replies", "value": "always"])
    try await store.setStealth(true)
    #expect(fake.calls("setting").last?.params == ["key": "stealth", "value": true])
    #expect(fake.calls("setting").allSatisfy { !$0.elevated })
    try await store.setKeepAwake(true)
    #expect(fake.calls("remote.keep_awake").last?.params == ["on": true])
    #expect(fake.calls("remote.keep_awake").last?.elevated == false)  // on power: no Face ID
    #expect(store.mac?.keepAwake == true)
}

@MainActor
@Test func keepingTheMacAwakeOnBatteryGoesWithTheUnlock() async throws {
    // Neither Pebble's bridge nor the mock wants Face ID for it (the bridge alignment review, 2026-10-31).
    let (store, fake) = await connectedStore { method, _ in method == "remote.keep_awake" ? ["keep_awake": true] : nil }
    fake.push("remote.mac", ["on_power": false, "charging": false, "battery_percent": 40, "keep_awake": false])
    #expect(await eventually { store.mac?.onPower == false })
    try await store.setKeepAwake(true)
    let call = try #require(fake.calls("remote.keep_awake").last)
    #expect(!call.elevated)
    #expect(store.mac?.keepAwake == true)
}

@MainActor
@Test func answersSendOneOptionOrWordsPerPrompt() async throws {
    let (store, fake) = await connectedStore(
        state: liveState, chat: Fixture.chatDetail(runs: [Fixture.runRow("r1", chat: "c1", state: "waiting_input")], questions: [Fixture.question("q1")]))
    _ = store.transcript(for: "c1")
    #expect(await eventually { !store.waiting.isEmpty })
    guard case .question(let card) = try #require(store.waiting.first) else { return }
    try await store.answer(card, with: ["tone": .option(id: "warm", text: "ignored")])
    #expect(
        fake.calls("question_answer").last?.params
            == ["id": "c1", "question_id": "q1", "revision": 1, "answers": ["tone": ["option_id": "warm"]]])
    try await store.answer(card, with: ["tone": .text("Playful but short")])
    #expect(fake.calls("question_answer").last?.params["answers"] == ["tone": ["text": "Playful but short"]])
    try await store.dismiss(card)
    #expect(fake.calls("question_cancel").last?.params == ["id": "c1", "question_id": "q1", "revision": 1])
}

@MainActor
@Test func stopPauseAndResumeNameTheConversationAndItsRun() async throws {
    let (store, fake) = await connectedStore(state: liveState)
    try await store.stop(chat: "c1")
    #expect(fake.calls("cancel").last?.params == ["id": "c1"])  // App.vue stop(): the live run, else a waiting one
    try await store.pause(chat: "c1")
    #expect(fake.calls("run_pause").last?.params == ["id": "c1", "run_id": "r1"])
    fake.push("run", ["chat_id": "c1", "run_id": "r1", "state": "paused"])
    #expect(await eventually { store.liveRuns.first?.state == .paused })
    try await store.resume(chat: "c1")
    #expect(fake.calls("run_resume").last?.params == ["id": "c1", "run_id": "r1"])
}

@MainActor
@Test func stopEverythingCancelsEachRunTheWorkingOneFirst() async throws {
    let state = Fixture.stateJSON(
        chats: [Fixture.chatRow("c1", "a", updated: 2), Fixture.chatRow("c2", "b", updated: 1)],
        runs: [
            Fixture.runRow("r1", chat: "c1", state: "waiting_input", created: 5),
            Fixture.runRow("r2", chat: "c2", state: "running", created: 1),
        ], active: "c2", activeRun: "r2")
    let (store, fake) = await connectedStore(state: state)
    // Pebble frees the worker once the working run has stopped.
    fake.react { client, call in
        if call.method == "cancel", call.params["run_id"] == "r2" {
            client.push("run", ["chat_id": "c2", "run_id": "r2", "state": "stopped", "elapsed": 4])
            client.push("idle", ["chat_id": "c2", "run_id": "r2"])
        }
    }
    store.pause = { _ in try? await Task.sleep(for: .milliseconds(5)) }
    #expect(store.liveRuns.map(\.id) == ["r1", "r2"])
    try await store.stopEverything()
    #expect(
        fake.calls("cancel").map(\.params) == [["id": "c2", "run_id": "r2"], ["id": "c1", "run_id": "r1"]])
}

@MainActor
@Test func eventsReachTheScreensAsTheyHappen() async throws {
    let (store, fake) = await connectedStore(state: liveState)
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading })
    fake.push("progress", ["chat_id": "c1", "run_id": "r1", "label": "Reading src/App.vue", "kind": "working", "tool": "Read", "activity": "reading"])
    #expect(await eventually { store.liveRuns.first?.status == .reading })
    #expect(store.liveRuns.first?.activity == "Reading src/App.vue")
    #expect(transcript.run?.status == .reading)
    fake.push("progress", ["chat_id": "c1", "run_id": "r1", "label": "Reading src/App.vue", "kind": "done", "tool": "Read", "activity": .null])
    fake.push("token", ["chat_id": "c1", "id": "m2", "text": "Found it."])
    #expect(await eventually { transcript.items.last?.id == "m/m2" })
    #expect(store.chats.first?.status == .writing)
    fake.push("reply_banner", ["chat_id": "c1", "run_id": "r1", "title": "Pebble finished", "body": "Fix the login"])
    #expect(await eventually { store.banner?.title == "Pebble finished" })
    store.dismissBanner()
    #expect(store.banner == nil)
}

@MainActor
@Test func aSlashCommandsReplyIsReadBack() async throws {
    let (store, fake) = await connectedStore { method, _ in
        method == "send" ? ["message_id": "cmd-1", "command": true] : nil
    }
    let transcript = store.transcript(for: "c1")
    #expect(await eventually { !transcript.isLoading })
    let reads = fake.calls("remote.chat_tail").count
    try await store.send("/help", in: "c1")
    #expect(await eventually { fake.calls("remote.chat_tail").count > reads })
}

@MainActor
@Test func searchMatchesTitlesHereAndMessagesOnTheMac() async throws {
    let state = Fixture.stateJSON(chats: [
        Fixture.chatRow("c1", "Fix the login redirect loop", updated: 3), Fixture.chatRow("c2", "Weather", updated: 2),
        Fixture.chatRow("c3", "Release notes", updated: 1),
    ])
    let (store, fake) = await connectedStore(state: state) { method, params in
        method == "chat_search" && params["query"] == "cookie" ? ["query": "cookie", "matches": [["id": "c3", "excerpt": "…the cookie…"], ["id": "c9", "excerpt": "?"]]] : nil
    }
    #expect(try await store.search("login").map(\.id) == ["c1"])
    #expect(try await store.search("cookie").map(\.id) == ["c3"])  // unknown ids are skipped
    #expect(fake.calls("chat_search").last?.params == ["query": "cookie"])
    #expect(try await store.search("  ").count == 3)
}

@MainActor
@Test func aNewConversationOpensAndTakesItsFirstMessage() async throws {
    let (store, fake) = await connectedStore { method, _ in
        switch method {
        case "new_chat": Fixture.chatDetail("c5", title: "New conversation")
        case "send": ["message_id": "m1", "run_id": "r1"]
        default: nil
        }
    }
    let id = try await store.newChat(firstMessage: "Plan the onboarding emails")
    #expect(id == "c5")
    #expect(fake.calls("new_chat").last?.params == [:])
    #expect(fake.calls("send").last?.params == ["id": "c5", "text": "Plan the onboarding emails"])
    #expect(store.transcript(for: "c5").items.first?.id == "m/m1")
    #expect(store.chats.contains { $0.id == "c5" })
}

@MainActor
@Test func pairingKeepsTheMacAndForgettingRemovesBoth() async throws {
    let kept = InMemoryPairedMacStore()
    let (store, fake) = await connectedStore(macStore: kept)
    let link = try #require(PairingLink(string: "pebble-remote://pair?v=1&bid=b1&name=Studio%20Mac&pin=p1&code=c1&ep=192.168.1.20:47800"))
    try await store.pair(using: link, deviceName: "iPhone 17")
    #expect(store.pairedMac?.bridgeID == "b1")
    #expect(try kept.load()?.deviceID == "d1")
    // A store made later finds it.
    #expect(RemoteStore(client: FakeClient(), macStore: kept).pairedMac?.bridgeID == "b1")
    await store.forgetMac()
    #expect(fake.calls("remote.revoke_device").last?.params == ["device_id": "d1"])
    #expect(try kept.load() == nil)
    #expect(store.pairedMac == nil && store.pebble == nil && store.chats.isEmpty && store.bridge == nil)
}

@MainActor
@Test func failuresWithoutPebblesWordsUseTheStoresOwn() async throws {
    let (store, _) = await connectedStore { method, _ in
        if method == "chat_rename" { throw RemoteCallError.timedOut }
        if method == "run_pause" { throw RemoteCallError.notConnected }
        return nil
    }
    await #expect(throws: RemoteCallError.timedOut) { try await store.rename(chat: "c1", to: "Login") }
    #expect(store.notice?.code == StoreWords.Code.timedOut)
    await #expect(throws: RemoteCallError.notConnected) { try await store.pause(chat: "c1") }
    #expect(store.notice?.message == StoreWords.notConnected)
}

@MainActor
@Test func renamingShowsPebblesTitle() async throws {
    let (store, _) = await connectedStore { method, _ in
        method == "chat_rename" ? ["id": "c1", "title": "Login loop"] : nil
    }
    try await store.rename(chat: "c1", to: "  Login   loop ")
    #expect(store.chats.first?.title == "Login loop")
}

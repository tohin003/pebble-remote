import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// The Control tab and Settings (v0.2 P1) against a FakeClient.

@MainActor
private func controlStore(
    state: JSONValue = Fixture.stateJSON(),
    extra: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try extra(method, params) { return answer }
        switch method {
        case "state": return state
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        default: return .bool(true)
        }
    }
    var methods = BridgeInfo.test().methods
    methods.formUnion(["model_profiles", "model_select", "model_effort", "remote.devices", "remote.screenshot"])
    let store = RemoteStore(client: fake)
    fake.push(.welcome(.test(methods: methods)))
    _ = await eventually { store.pebble != nil }
    return (store, fake)
}

@Test func projectsAreTheConversationsFoldersNewestFirst() {
    var world = PebbleWorld()
    world.load(
        StateDTO(
            json: Fixture.stateJSON(chats: [
                Fixture.chatRow("c1", "a", workspace: "/Users/me/Projects/pebble-web", updated: 5),
                Fixture.chatRow("c2", "b", workspace: "/Users/me/Projects/pebble-docs", updated: 9),
                Fixture.chatRow("c3", "c", workspace: "/Users/me/Projects/pebble-web", updated: 12),
                Fixture.chatRow("c4", "d", updated: 20),
            ]))!)
    let projects = world.projects()
    #expect(projects.map(\.name) == ["pebble-web", "pebble-docs"])
    #expect(projects.first?.path == "/Users/me/Projects/pebble-web")
    #expect(projects.first?.lastUsed == Fixture.at(12))
}

@Test func settingsReadEveryKeyPebbleReports() {
    let settings = PebbleSettings(
        json: [
            "theme": "dark", "reduced_motion": true, "stealth": true, "memory_enabled": false,
            "memory_layers": ["working": true, "episodic": false],
            "permissions": Fixture.permissions, "fast_replies": "always",
            "companion": ["pointer": true, "reactions": false, "status_words": "fixed", "ui_guidance": true],
            "git_decisions": ["push": true], "future": 1,
        ])
    #expect(settings.theme == "dark" && settings.reducedMotion && settings.stealth && !settings.memoryEnabled)
    #expect(settings.memoryLayers == ["working": true, "episodic": false])
    #expect(settings.mode == .ask && settings.tools["files"] == true && settings.tools["screen"] == false)
    #expect(settings.fastReplies == .always)
    #expect(settings.companion["status_words"] == "fixed")
    #expect(settings.gitDecisions == ["push": true])
}

@MainActor
@Test func theStorePublishesSettingsAndProjects() async throws {
    let (store, _) = await controlStore()
    #expect(store.settings?.tools["terminal"] == true)
    #expect(store.settings?.companion["pointer"] == true)
    #expect(store.projects.map(\.name) == ["pebble-web"])
    #expect(store.currentModelID == "chatgpt")
}

@MainActor
@Test func aNewConversationCanStartInAKnownProject() async throws {
    let (store, fake) = await controlStore { method, _ in
        method == "new_chat" ? Fixture.chatDetail("c7", title: "New conversation") : JSONValue?.none
    }
    let project = try #require(store.projects.first)
    let id = try await store.newChat(firstMessage: nil, in: project)
    #expect(id == "c7")
    #expect(fake.calls("new_chat").last?.params == ["workspace": "/Users/me/Projects/pebble-web"])
    _ = try await store.newChat(firstMessage: nil)
    #expect(fake.calls("new_chat").last?.params == [:])
}

@MainActor
@Test func modelsLoadAndChange() async throws {
    let (store, fake) = await controlStore { method, _ in
        method == "model_profiles"
            ? [
                [
                    "id": "chatgpt", "name": "ChatGPT", "kind": "chatgpt", "model": "gpt-5.1", "display_name": "GPT-5.1",
                    "provider_name": "ChatGPT", "context": 272_000, "tools": true, "email": "never-read",
                ],
                ["id": "default-local", "name": "Qwen 3.5 9B", "kind": "gguf", "path": "/m.gguf", "context": 32768, "tools": true],
            ] : nil
    }
    await store.loadControlLists()
    #expect(store.models.map(\.name) == ["GPT-5.1", "Qwen 3.5 9B"])
    #expect(store.models.first?.efforts == ["low", "medium", "high"])  // the model in use: from state().model
    #expect(store.models.last?.isLocal == true)
    try await store.selectModel("default-local")
    #expect(fake.calls("model_select").last?.params == ["profile_id": "default-local"])
    try await store.setEffort("high")
    #expect(fake.calls("model_effort").last?.params == ["effort": "high"])
}

@MainActor
@Test func settingsSendTheWholeValuePebbleExpects() async throws {
    let (store, fake) = await controlStore()
    try await store.setTheme("dark")
    #expect(fake.calls("setting").last?.params == ["key": "theme", "value": "dark"])
    #expect(fake.calls("setting").last?.elevated == false)
    try await store.setMemoryLayer("episodic", on: false)
    #expect(
        fake.calls("setting").last?.params["value"]
            == ["working": true, "episodic": false, "semantic": true, "procedural": true, "temporal": true, "profile": true])
    try await store.setToolSwitch("screen", on: true)
    let call = try #require(fake.calls("setting").last)
    #expect(call.elevated && call.params["key"] == "permissions")
    #expect(call.params["value"]?["tools"]?["screen"] == true)
    #expect(call.params["value"]?["tools"]?["terminal"] == true)  // the other groups as they were
    #expect(call.params["value"]?["mode"] == "ask")
}

@MainActor
@Test func aScreenshotArrivesAsImageData() async throws {
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    let (store, fake) = await controlStore { method, _ in
        method == "remote.screenshot"
            ? [
                "taken_at": 1_761_759_000_123,
                "displays": [["index": 0, "width": 2560, "height": 1600, "format": "jpeg", "data": .string(jpeg.base64EncodedString())]],
            ] : nil
    }
    let picture = try await store.screenshot()
    #expect(fake.calls("remote.screenshot").last?.params == ["display": .null])
    #expect(picture.displays.first?.data == jpeg)
    #expect(picture.displays.first?.width == 2560)
    #expect(picture.takenAt == Date(timeIntervalSince1970: 1_761_759_000.123))
    _ = try await store.screenshot(display: 1)
    #expect(fake.calls("remote.screenshot").last?.params == ["display": 1])
}

@MainActor
@Test func pairedPhonesLoadAndCanBeRemoved() async throws {
    let (store, fake) = await controlStore { method, _ in
        method == "remote.devices"
            ? [
                ["device_id": "d1", "name": "iPhone 17", "paired_at": 1_761_700_000_000, "last_seen": 1_761_759_000_000, "current": true],
                ["device_id": "d2", "name": "iPad", "paired_at": 1_761_000_000, "last_seen": .null, "current": false],
            ] : nil
    }
    await store.loadControlLists()
    #expect(store.devices.map(\.name) == ["iPhone 17", "iPad"])
    #expect(store.devices.first?.isCurrent == true)
    #expect(store.devices.last?.pairedAt == Date(timeIntervalSince1970: 1_761_000_000))  // an older bridge's seconds
    try await store.revokeDevice(store.devices[1])
    #expect(fake.calls("remote.revoke_device").last?.params == ["device_id": "d2"])
    #expect(store.devices.map(\.id) == ["d1"])
}

@MainActor
@Test func memoryLayersCarryPebblesNamesAndSwitches() async throws {
    var state = Fixture.stateJSON()
    if case .object(var object) = state {
        object["memory"] = ["enabled": true, "strategy": "v2", "types": [["id": "working", "name": "Working context", "count": 3, "enabled": true]]]
        if case .object(var settings)? = object["settings"] {
            settings["memory_layers"] = ["working": true, "episodic": false, "semantic": true, "procedural": true, "temporal": true, "profile": true]
            object["settings"] = .object(settings)
        }
        state = .object(object)
    }
    let (store, _) = await controlStore(state: state)
    #expect(store.memoryLayers.map(\.name) == ["Working context", "Past experiences", "Facts & knowledge", "Procedures", "Time-sensitive information", "Your preferences"])
    #expect(store.memoryLayers.first?.count == 3 && store.memoryLayers[1].isOn == false && store.memoryLayers[2].isOn)
}

@MainActor
@Test func settingsTheBridgeGuardsAskForFaceID() async throws {
    let fake = FakeClient { method, _ in method == "state" ? Fixture.stateJSON() : .bool(true) }
    let store = RemoteStore(client: fake)
    var bridge = BridgeInfo.test()
    bridge.elevated = ["approve", "setting:permissions", "setting:stealth"]
    fake.push(.welcome(bridge))
    #expect(await eventually { store.pebble != nil })
    try await store.setStealth(true)
    #expect(fake.calls("setting").last?.elevated == true && fake.calls("setting").last?.reason == "Change Pebble's settings")
    try await store.setTheme("dark")
    #expect(fake.calls("setting").last?.elevated == false)
    try await store.setPermissionMode(.auto)
    #expect(fake.calls("setting").last?.elevated == true && fake.calls("setting").last?.reason == "Change Pebble's permissions")
    // A bridge that names no keys: permissions only.
    fake.push(.welcome(.test()))
    #expect(await eventually { store.bridge?.elevated.contains("setting:stealth") == false })
    #expect(store.settingNeedsProof("permissions") && !store.settingNeedsProof("stealth"))
}

@MainActor
@Test func theUnlockStateFollowsTheClient() async throws {
    let (store, fake) = await controlStore()
    store.clock = { Fixture.at(0) }
    #expect(store.unlockedUntil == nil && !store.isUnlocked)
    try await store.unlock()
    let call = try #require(fake.calls("remote.unlock").last)
    #expect(call.elevated && call.params == [:] && call.reason == "Let this iPhone act on your Mac")
    fake.push(.unlocked(until: Fixture.at(900)))
    #expect(await eventually { store.unlockedUntil == Fixture.at(900) })
    #expect(store.isUnlocked)
    store.clock = { Fixture.at(901) }
    #expect(!store.isUnlocked)  // past its time, until the client says otherwise
    fake.push(.unlocked(until: nil))
    #expect(await eventually { store.unlockedUntil == nil })
}

/// Pebble's Stealth setting as the fake's `state` reports it: whatever the last `setting` call chose.
private final class StealthSetting: Sendable {
    private let on = Mutex(false)

    func answer(_ method: String, _ params: JSONValue) -> JSONValue {
        if method == "setting", params["key"] == "stealth", let wanted = params["value"]?.bool {
            on.withLock { $0 = wanted }
        }
        guard method == "state", case .object(var state) = Fixture.stateJSON(),
            case .object(var settings)? = state["settings"]
        else { return .bool(true) }
        settings["stealth"] = .bool(on.withLock { $0 })
        state["settings"] = .object(settings)
        return .object(state)
    }
}

/// Design review A2: switches show only what Pebble confirmed, so a setter returns once the store shows Pebble's new
/// value, never before (else a switch would sit still after its spinner ends).
@MainActor
@Test func aSettingReturnsOnceTheStoreShowsPebblesNewValue() async throws {
    let setting = StealthSetting()
    let fake = FakeClient { method, params in setting.answer(method, params) }
    let store = RemoteStore(client: fake)
    fake.push(.welcome(.test()))
    #expect(await eventually { store.pebble?.stealth == false })
    try await store.setStealth(true)
    #expect(store.pebble?.stealth == true)
    try await store.setStealth(false)
    #expect(store.pebble?.stealth == false)
}

/// The chat's model and effort menus (asked for 2026-10-30): the efforts and Pebble's recommended one come from its
/// state, and the menus wait while a task runs, because Pebble refuses changes then.
@MainActor
@Test func effortsAndTheWorkingTaskComeFromPebblesState() async throws {
    var state = Fixture.stateJSON(active: "c1")
    if case .object(var object) = state, case .object(var model)? = object["model"] {
        model["default_effort"] = "high"
        object["model"] = .object(model)
        state = .object(object)
    }
    let answer = state
    let fake = FakeClient { method, _ in method == "state" ? answer : .bool(true) }
    let store = RemoteStore(client: fake)
    fake.push(.welcome(.test()))
    #expect(await eventually { store.pebble != nil })
    #expect(store.pebble?.efforts == ["low", "medium", "high"])
    #expect(store.pebble?.effort == "medium" && store.pebble?.defaultEffort == "high")
    #expect(store.isPebbleWorking)
}

/// Pebble's model and effort as the fake's `state` reports them: whatever the last change chose.
private final class ModelAndEffort: Sendable {
    private let chosen = Mutex<[String: String]>(["profile": "chatgpt", "effort": "medium"])

    func answer(_ method: String, _ params: JSONValue) -> JSONValue {
        switch method {
        case "model_select": chosen.withLock { $0["profile"] = params["profile_id"]?.string }
        case "model_effort": chosen.withLock { $0["effort"] = params["effort"]?.string }
        case "state":
            guard case .object(var state) = Fixture.stateJSON(), case .object(var model)? = state["model"] else { break }
            let now = chosen.withLock { $0 }
            model["profile_id"] = now["profile"].map(JSONValue.string) ?? .null
            model["effort"] = now["effort"].map(JSONValue.string) ?? .null
            state["model"] = .object(model)
            return .object(state)
        default: break
        }
        return .bool(true)
    }
}

/// The menus show only what Pebble confirmed, so a change returns once the store shows it.
@MainActor
@Test func aModelOrEffortChangeReturnsOnceTheStoreShowsIt() async throws {
    let pebble = ModelAndEffort()
    let fake = FakeClient { method, params in pebble.answer(method, params) }
    let store = RemoteStore(client: fake)
    fake.push(.welcome(.test()))
    #expect(await eventually { store.currentModelID == "chatgpt" })
    #expect(!store.isPebbleWorking)
    try await store.selectModel("local")
    #expect(store.currentModelID == "local")
    try await store.setEffort("high")
    #expect(store.pebble?.effort == "high")
}

/// R1 with Tailscale added after pairing: the Mac's own list of addresses (`remote.status`) joins the pairing, current
/// ones first, so the next connection also tries the tailnet. Invalid hosts are dropped.
@MainActor
@Test func theMacsReportedAddressesJoinThePairing() async throws {
    let lan = Endpoint(host: "192.168.1.20", port: 7443)
    let tailnet = Endpoint(host: "100.101.102.103", port: 7443)
    let fake = FakeClient { method, _ in
        switch method {
        case "state": Fixture.stateJSON()
        case "remote.status":
            ["mac": ["name": "Studio Mac"], "pebble": ["running": true, "version": "1.9.28"],
             "bridge": ["version": "0.6", "epoch": 1, "endpoints": ["100.101.102.103:7443", "192.168.1.20:7443", "bad host:1"]]]
        default: .bool(true)
        }
    }
    let saved = InMemoryPairedMacStore()
    let paired = PairedMac(bridgeID: "b1", name: "Studio Mac", deviceID: "d1", pin: "p1", endpoints: [lan], pairedAt: Fixture.t0)
    let store = RemoteStore(client: fake, pairedMac: paired, macStore: saved)
    fake.push(.welcome(.test()))
    #expect(await eventually { store.pairedMac?.endpoints == [tailnet, lan] })
    #expect((try saved.load())?.endpoints == [tailnet, lan])
}


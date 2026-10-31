import Foundation
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// Lane S: the Settings controls that were "On your Mac" rows send what Pebble's own Settings send (read-only Pebble
// checkout: app.py's dispatcher, AdvancedSettings.vue, StorageSettings.vue, TelemetrySettings.vue,
// NotificationSettings.vue), read Pebble's answers without trusting them, ask for Face ID where contract 3.6 says, and
// work in the demo.

/// The methods lane S's controls call: a bridge that offers them (2.0.0's welcome lists them all).
private let settingsMethods: Set<String> = [
    "state", "get_chat", "setting", "memory_list", "memory_candidates", "memory_resolve", "memory_maintain",
    "memory_save", "memory_clear", "extensions", "skill_inspect", "extension_toggle", "storage_summary",
    "storage_refresh", "storage_trash_all", "storage_purge_all", "telemetry_get", "telemetry_set", "shell_grants",
    "shell_grant_remove", "notification_status", "notification_mute", "model_load", "model_unload",
]

/// What 2.0.0's bridge elevates among them (remote_policy.py ELEVATED_ALWAYS).
private let settingsElevated: Set<String> = [
    "memory_clear", "extension_toggle", "storage_trash_all", "storage_purge_all", "shell_grant_remove",
]

/// A switch a fake bridge's answers can read (they run on any thread).
private final class Flag: Sendable {
    private let state = Mutex(false)
    var isOn: Bool { state.withLock { $0 } }
    func turnOn() { state.withLock { $0 = true } }
}

/// `extensions` rows as Pebble lists them, with fields of the wrong type and a row without an id.
private let extensionRows: JSONValue = [
    [
        "id": "s1", "kind": "skill", "name": "Release checklist", "enabled": true, "content": "# Steps",
        "capabilities": ["task guidance"],
        "config": [
            "bundle_digest": "abc", "main": "SKILL.md",
            "files": [
                ["path": "SKILL.md", "bytes": 10, "sha256": "aa"],
                ["path": "references/a.MD", "bytes": 20, "sha256": "bb"],
                ["path": "scripts/run.sh", "bytes": 30, "sha256": "cc"], ["bytes": 1],
            ],
        ],
    ],
    [
        "id": "c1", "kind": "plugin", "name": "GitHub", "enabled": false, "content": "{}",
        "capabilities": ["search_issues", 4],
        "config": [
            "url": "https://example.com/mcp", "tools": ["search_issues"], "catalogue_digest": "d1", "protocol": "2025-06-18",
            "schemas": [["name": "search_issues"]], "launch_files": .null, "package_digest": "p1",
            "auth_binding": ["grant_id": "g"],
        ],
    ],
    [
        "id": "c2", "kind": "plugin", "name": "Local notes", "enabled": true,
        "config": ["transport": "stdio", "command": "/usr/local/bin/notes-mcp", "url": "", "schemas": []],
    ],
    ["id": "h1", "kind": "hook", "name": "Ask first", "enabled": "yes", "config": "unreadable"],
    ["kind": "skill", "name": "no id"],
]

@MainActor
private func settingsStore(
    elevated: Set<String> = settingsElevated,
    answer: @escaping @Sendable (String, JSONValue) throws -> JSONValue? = { _, _ in nil }
) async -> (RemoteStore, FakeClient) {
    let fake = FakeClient { method, params in
        if let answer = try answer(method, params) { return answer }
        switch method {
        case "state": return Fixture.stateJSON()
        case "get_chat", "remote.chat_tail": return Fixture.chatDetail()
        default: return .bool(true)
        }
    }
    let store = RemoteStore(client: fake)
    fake.push(.status(ConnectionStatus(phase: .connected, route: .lan, roundTrip: 6)))
    fake.push(
        .welcome(
            BridgeInfo(
                bridgeVersion: "0.1", macName: "Studio Mac", pebbleRunning: true, pebbleVersion: "2.0.0",
                methods: settingsMethods, elevated: elevated, resumed: false)))
    _ = await eventually { store.pebble != nil && !store.projects.isEmpty }
    return (store, fake)
}

@MainActor
private func demoStore() async -> RemoteStore {
    let client = DemoClient(pace: 0, autoplay: false, now: { Fixture.t0 })
    let store = RemoteStore(client: client, pairedMac: DemoClient.pairedMac(at: Fixture.t0), isDemo: true)
    store.start()
    _ = await eventually { store.pebble != nil && !store.memoryLayers.isEmpty }
    return store
}

@MainActor
struct SettingsControlsTests {
    // MARK: - Settings › Memory (SY-12, SY-13, SY-16, SY-19)

    @Test func learningCandidatesAreReadForEveryConversationAndOnlyPebblesThreeStatesShow() async throws {
        let rows: JSONValue = [
            [
                "id": "a", "kind": "profile", "status": "conflict", "reason": "active_value_differs",
                "content": "Use 24-hour times.", "scope": "global", "updated": 1_761_000_000,
            ],
            [
                "id": "b", "kind": "procedural", "status": "pending", "reason": "wait_for_settled_test_evidence",
                "content": "",
            ],
            ["id": "c", "kind": "semantic", "status": "unsupported", "reason": 7, "content": "x", "scope": "chat:c1"],
            ["id": "d", "kind": "profile", "status": "promoted", "content": "Saved already."],
            ["kind": "profile", "status": "pending", "content": "no id"],
            "not a row",
        ]
        let (store, fake) = await settingsStore { method, _ in method == "memory_candidates" ? rows : nil }
        let candidates = try await store.memoryCandidates()
        #expect(candidates.map(\.id) == ["a", "b", "c"])
        #expect(candidates[0].disagrees && !candidates[1].disagrees && !candidates[2].disagrees)
        #expect(candidates[0].updated == Date(timeIntervalSince1970: 1_761_000_000))
        #expect(candidates[2].reason == nil, "a reason that isn't words reads as none")
        #expect(fake.calls("memory_candidates").last?.params == [:], "no conversation: every conversation's")
        // An answer that isn't a list is no candidates, never a crash.
        let (other, _) = await settingsStore { method, _ in method == "memory_candidates" ? ["rows": rows] : nil }
        #expect(try await other.memoryCandidates().isEmpty)
    }

    @Test func aCandidateIsDecidedAndUpkeepRunsWithPebblesParamsAndNoFaceID() async throws {
        let (store, fake) = await settingsStore()
        let candidate = MemoryCandidate(id: "a", kind: "profile", status: "conflict")
        try await store.decide(candidate, useValue: true)
        try await store.decide(candidate, useValue: false)
        let decisions = fake.calls("memory_resolve")
        #expect(
            decisions.map(\.params) == [["candidate_id": "a", "accept": true], ["candidate_id": "a", "accept": false]])
        try await store.checkWaitingMemories()
        let check = try #require(fake.calls("memory_maintain").last)
        #expect(check.params == [:])
        #expect((decisions + [check]).allSatisfy { !$0.elevated })
    }

    @Test func aMemorySavedByHandSendsWhatPebblesFormSends() async throws {
        let (store, fake) = await settingsStore()
        try await store.saveMemory("Prefers metric units.", in: "profile", recall: .personal, expires: nil)
        #expect(
            fake.calls("memory_save").last?.params
                == ["kind": "profile", "content": "Prefers metric units.", "scope": "global", "expires": .null])
        // A project memory names a conversation of that project; Pebble keeps it with the folder.
        let project = try #require(store.projects.first)
        try await store.saveMemory("Deploys need a review.", in: "semantic", recall: .project(project), expires: nil)
        #expect(
            fake.calls("memory_save").last?.params
                == [
                    "kind": "semantic", "content": "Deploys need a review.", "scope": "project", "id": "c1",
                    "expires": .null,
                ])
        let when = Fixture.at(86_400)
        try await store.saveMemory("Rain on Saturday.", in: "temporal", recall: .personal, expires: when)
        #expect(fake.calls("memory_save").last?.params["expires"] == .double(when.timeIntervalSince1970))
        #expect(fake.calls("memory_save").allSatisfy { !$0.elevated })
    }

    @Test func aProjectWithoutAConversationIsRefusedInPebblesWordsBeforeAnyCall() async throws {
        let (store, fake) = await settingsStore()
        let nowhere = ProjectRef(folder: "/Users/me/Projects/gone")
        await #expect(throws: RemoteCallError.self) {
            try await store.saveMemory("x", in: "profile", recall: .project(nowhere), expires: nil)
        }
        #expect(store.notice?.message == "Connect a project before saving project memory.")
        #expect(fake.calls("memory_save").isEmpty)
    }

    @Test func forgettingEveryMemoryAsksFaceIDAndShowsPebblesRefusal() async throws {
        let (store, fake) = await settingsStore()
        try await store.forgetAllMemories()
        let call = try #require(fake.calls("memory_clear").last)
        #expect(call.elevated && call.params == [:] && call.reason == "Forget all memories")
        let (busy, _) = await settingsStore { method, _ in
            if method == "memory_clear" {
                let words = "Stop the current task before forgetting memories."
                throw RemoteCallError.refused(PersonFacingError(message: words))
            }
            return nil
        }
        await #expect(throws: RemoteCallError.self) { try await busy.forgetAllMemories() }
        #expect(busy.notice?.message == "Stop the current task before forgetting memories.")
    }

    @Test func theDemosCandidatesWaitForTheTaskThenAreDecidedAndChecked() async throws {
        let store = await demoStore()
        #expect(await eventually { store.isPebbleWorking })
        let candidates = try await store.memoryCandidates()
        #expect(Set(candidates.map(\.status)) == ["pending", "conflict", "unsupported"])
        let conflict = candidates.first { $0.disagrees }
        let disagreeing = try #require(conflict)
        await #expect(throws: RemoteCallError.self) { try await store.decide(disagreeing, useValue: true) }
        #expect(store.notice?.message == "Wait for the current task before resolving a memory conflict.")
        await #expect(throws: RemoteCallError.self) { try await store.checkWaitingMemories() }
        #expect(store.notice?.message == "Wait for the current task before running manual maintenance.")
        try await store.stop(chat: DemoData.loginChat)
        #expect(await eventually { !store.isPebbleWorking })
        try await store.decide(disagreeing, useValue: true)
        #expect(try await store.memories(in: "profile").records.contains { $0.content == disagreeing.content })
        let recipes = try await store.memories(in: "procedural").records.count
        try await store.checkWaitingMemories()
        #expect(try await store.memoryCandidates().map(\.status) == ["unsupported"])
        #expect(try await store.memories(in: "procedural").records.count == recipes + 1)
    }

    @Test func theDemoSavesMemoriesByHandAsPebbleChecksThemThenForgetsEverything() async throws {
        let store = await demoStore()
        try await store.saveMemory("Prefers metric units.", in: "profile", recall: .personal, expires: nil)
        let preferences = try await store.memories(in: "profile").records
        #expect(preferences.contains { $0.content == "Prefers metric units." && $0.origin == "user" })
        let found = store.projects.first { $0.name == "pebble-web" }
        let project = try #require(found)
        try await store.saveMemory("Deploys need a review.", in: "semantic", recall: .project(project), expires: nil)
        let facts = try await store.memories(in: "semantic").records
        #expect(facts.contains { $0.scope == project.path && $0.content == "Deploys need a review." })
        await #expect(throws: RemoteCallError.self) {
            try await store.saveMemory("Rain.", in: "temporal", recall: .personal, expires: Fixture.at(-60))
        }
        #expect(store.notice?.message == "The expiry must be in the future.")
        await #expect(throws: RemoteCallError.self) {
            try await store.saveMemory("Rain.", in: "temporal", recall: .personal, expires: nil)
        }
        #expect(store.notice?.message == "Time-sensitive memories need an expiry date.")
        try await store.saveMemory("Rain on Saturday.", in: "temporal", recall: .personal, expires: Fixture.at(86_400))
        // Forget all waits for the task, then empties every layer and the candidates.
        #expect(await eventually { store.isPebbleWorking })
        await #expect(throws: RemoteCallError.self) { try await store.forgetAllMemories() }
        #expect(store.notice?.message == "Stop the current task before forgetting memories.")
        try await store.stop(chat: DemoData.loginChat)
        #expect(await eventually { !store.isPebbleWorking })
        try await store.forgetAllMemories()
        for layer in RemoteStore.memoryLayerNames {
            #expect(try await store.memories(in: layer).records.isEmpty, "\(layer)")
        }
        #expect(try await store.memoryCandidates().isEmpty)
        #expect(await eventually { store.memoryLayers.allSatisfy { ($0.count ?? 0) == 0 } })
    }

    // MARK: - Settings › Skills & connectors (SK-04, SK-05, SK-06, SK-09)

    @Test func extensionsAreReadAsTheMacsCardsAndReviews() async throws {
        let (store, fake) = await settingsStore { method, _ in method == "extensions" ? extensionRows : nil }
        let items = try await store.extensions()
        #expect(items.map(\.id) == ["s1", "c1", "c2", "h1"])
        #expect(fake.calls("extensions").last?.params == [:])
        let skill = try #require(items[0].skill)
        #expect(skill.snapshot == "abc" && skill.main == "SKILL.md")
        #expect(skill.files.map(\.path) == ["SKILL.md", "references/a.MD", "scripts/run.sh"])
        #expect(skill.files.map(\.readable) == [false, true, false], "the main file and a script Pebble won't read")
        let github = try #require(items[1].connector)
        #expect(items[1].capabilities == ["search_issues"] && !items[1].enabled)
        #expect(github.transport == "http" && github.protocolEra == "legacy")
        #expect(github.address == "https://example.com/mcp")
        #expect(github.reviewedVersion == "d1" && github.protocolVersion == "2025-06-18")
        #expect(github.packageChecksum == "p1")
        #expect(github.holdsGrant && github.launchFiles == nil)
        #expect(github.schemas?.contains("search_issues") == true && github.schemas?.contains("\n") == true)
        let local = try #require(items[2].connector)
        #expect(local.transport == "stdio" && local.address == "/usr/local/bin/notes-mcp")
        #expect(!local.holdsGrant && local.schemas == nil && local.reviewedVersion == nil)
        #expect(items[3].connector == nil && items[3].skill == nil && !items[3].enabled, "a hook, read without trust")
    }

    @Test func aSkillsFileIsReadAPageAtATimeFromItsPinnedSnapshot() async throws {
        let (store, fake) = await settingsStore { method, params in
            guard method == "skill_inspect" else { return nil }
            // Asked for another file, it answers with this one's page: never shown as the other's.
            let asked = params["reference"] ?? .null
            let path: JSONValue = asked == "references/other.md" ? "references/a.md" : asked
            return ["path": path, "untrusted_source": "page", "next_offset": params["offset"] == 0 ? 3000 : .null]
        }
        let item = ExtensionItem(
            id: "s1", kind: "skill", name: "Release checklist",
            skill: .init(snapshot: "abc", main: "SKILL.md", files: []))
        let first = try await store.skillText(item, file: "references/a.md")
        #expect(first == SkillTextPage(path: "references/a.md", text: "page", nextOffset: 3000))
        #expect(
            fake.calls("skill_inspect").last?.params
                == ["id": "s1", "digest": "abc", "reference": "references/a.md", "offset": 0])
        let second = try await store.skillText(item, file: "references/a.md", from: 3000)
        #expect(second.nextOffset == nil)
        // Another file's page is never shown as this one's.
        await #expect(throws: RemoteCallError.self) { try await store.skillText(item, file: "references/other.md") }
        #expect(store.notice?.message == StoreWords.unreadableAnswer)
        // A skill without a pinned snapshot has nothing to read.
        let calls = fake.calls("skill_inspect").count
        await #expect(throws: RemoteCallError.self) {
            try await store.skillText(ExtensionItem(id: "s2", kind: "skill", name: "x"), file: "a.md")
        }
        #expect(fake.calls("skill_inspect").count == calls)
    }

    @Test func enablingOrDisablingAnExtensionAsksFaceID() async throws {
        let (store, fake) = await settingsStore()
        let item = ExtensionItem(id: "c1", kind: "plugin", name: "GitHub")
        try await store.setExtension(item, enabled: true)
        try await store.setExtension(item, enabled: false)
        let calls = fake.calls("extension_toggle")
        #expect(calls.map(\.params) == [["id": "c1", "enabled": true], ["id": "c1", "enabled": false]])
        #expect(calls.allSatisfy { $0.elevated })
        #expect(calls.map(\.reason) == ["Enable \u{201C}GitHub\u{201D}", "Disable \u{201C}GitHub\u{201D}"])
    }

    @Test func theDemosSkillsAndConnectorsAreReviewedPagedAndSwitched() async throws {
        let store = await demoStore()
        let items = try await store.extensions()
        #expect(items.map(\.kind) == ["skill", "plugin", "hook"])
        let skill = items[0]
        let readable = skill.skill?.files.filter(\.readable).map(\.path) ?? []
        #expect(readable == ["references/steps.md", "scripts/bump_version.py"])
        let first = try await store.skillText(skill, file: "references/steps.md")
        let next = try #require(first.nextOffset)
        #expect(first.text.count == 3000 && next == 3000)
        let second = try await store.skillText(skill, file: "references/steps.md", from: next)
        #expect(second.nextOffset == nil && !second.text.isEmpty)
        await #expect(throws: RemoteCallError.self) { try await store.skillText(skill, file: "SKILL.md") }
        #expect(store.notice?.message == "Choose a reference from this pinned manifest.")
        await #expect(throws: RemoteCallError.self) { try await store.skillText(skill, file: "assets/badge.png") }
        #expect(store.notice?.message == "This binary asset is inspectable by hash; text loading is unavailable.")
        let github = items[1]
        #expect(github.connector?.holdsGrant == true && !github.enabled)
        #expect(await eventually { store.isPebbleWorking })
        await #expect(throws: RemoteCallError.self) { try await store.setExtension(github, enabled: true) }
        #expect(store.notice?.message == "Stop the current task before changing extensions.")
        try await store.stop(chat: DemoData.loginChat)
        #expect(await eventually { !store.isPebbleWorking })
        try await store.setExtension(github, enabled: true)
        #expect(try await store.extensions()[1].enabled)
    }

    // MARK: - Settings › Data & storage (SD-11, SD-12, SD-14, SD-15)

    static let trashedRows: JSONValue = [
        ["chat_id": "t1", "title": "Old draft", "deleted": 1_761_000_000, "delete_after": 1_763_592_000],
        ["chat_id": "t2", "title": "Scratch", "deleted": 1_760_900_000],
    ]

    @Test func dataAndStorageReadsPebblesPageWithoutTrustingIt() async throws {
        let rows = Self.trashedRows
        let (store, fake) = await settingsStore { method, _ in
            guard method == "storage_summary" else { return nil }
            return [
                "events": [
                    ["at": 1, "kind": "storage", "text": "Copies in Documents are on."], ["kind": "x"], ["text": ""],
                    ["at": 2, "kind": "forgotten", "text": "Forgot 1 memory deleted from the Memory folder."],
                ],
                "documents": ["pending": ["waiting": ["conversations": 1, "memory": 2]]],
                "recently_deleted": rows,
            ]
        }
        let overview = try await store.storageOverview()
        #expect(overview.changes == ["Forgot 1 memory deleted from the Memory folder.", "Copies in Documents are on."])
        #expect(overview.checking == 3)
        #expect(overview.recentlyDeleted.map(\.id) == ["t1", "t2"] && store.trashed.map(\.id) == ["t1", "t2"])
        #expect(fake.calls("storage_summary").last?.params == [:])
        // A page without these parts reads as nothing changed, nothing waiting.
        #expect(StorageOverview(json: ["documents": ["pending": ["waiting": ["memory": -4]]]]) == StorageOverview())
    }

    @Test func updatingCopiesAndDeletingAllSendPebblesParams() async throws {
        let rows = Self.trashedRows
        let purged = Flag()
        let (store, fake) = await settingsStore { method, _ in
            switch method {
            case "storage_summary", "storage_refresh": return ["recently_deleted": purged.isOn ? [] : rows]
            case "storage_trash_all": return ["moved": 4, "kept": [["chat_id": "c1", "title": "Fix", "reason": "busy"]]]
            case "storage_purge_all":
                purged.turnOn()
                return ["deleted": 2, "kept": []]
            default: return nil
            }
        }
        let copied = try await store.updateCopies()
        #expect(copied.recentlyDeleted.count == 2)
        let refresh = try #require(fake.calls("storage_refresh").last)
        #expect(refresh.params == [:] && !refresh.elevated)
        #expect(try await store.moveAllToRecentlyDeleted() == ConversationsRemoved(count: 4, kept: 1))
        let trash = try #require(fake.calls("storage_trash_all").last)
        #expect(trash.elevated && trash.params == ["confirm": true] && trash.reason == "Move all to Recently deleted")
        #expect(try await store.deleteAllForGood() == ConversationsRemoved(count: 2))
        let purge = try #require(fake.calls("storage_purge_all").last)
        #expect(purge.elevated && purge.params == ["confirm": true] && purge.reason == "Delete all for good")
        #expect(store.trashed.isEmpty, "Recently deleted is read again")
    }

    @Test func theDemoUpdatesCopiesThenEmptiesEverythingButTheRunningTask() async throws {
        let store = await demoStore()
        let first = try await store.storageOverview()
        #expect(first.changes.count == 3 && first.checking == 1 && first.recentlyDeleted.isEmpty)
        let updated = try await store.updateCopies()
        #expect(updated.checking == 0 && updated.changes.first == "Forgot 1 memory deleted from the Memory folder.")
        #expect(await eventually { store.isPebbleWorking && store.chats.count > 2 })
        let listed = store.chats.count
        let moved = try await store.moveAllToRecentlyDeleted()
        #expect(moved == ConversationsRemoved(count: listed - 1, kept: 1), "the running task's conversation stays")
        #expect(store.trashed.count == listed - 1)
        #expect(await eventually { store.chats.map(\.id) == [DemoData.loginChat] }, "conversations open here leave too")
        #expect(try await store.deleteAllForGood() == ConversationsRemoved(count: listed - 1))
        #expect(store.trashed.isEmpty)
        #expect(try await store.storageOverview().changes.first == "Deleted \(listed - 1) conversation(s) for good.")
    }

    // MARK: - Settings › Privacy & Stealth: usage telemetry (SS-03, SS-06)

    @Test func telemetryIsReadAsTheMacReadsItWithoutTrustingItsNumbers() async throws {
        let (store, fake) = await settingsStore { method, _ in
            guard method == "telemetry_get" else { return nil }
            return [
                "enabled": false, "consented_at": .null, "current_consent_version": "pebble.telemetry.consent/1",
                "consent_text": "Pebble can keep a private usage log on this Mac.", "install_id": .null, "events": 2.7,
                "dropped": -3, "expired": "many", "refused": 1,
                "fields": ["run_settled": ["wall_ms_log2", 7, "steps"], "error": ["code"]],
                "limits": ["max_events": 1000, "max_bytes": 262_144, "retention_days": 30],
            ]
        }
        let status = try await store.telemetry()
        #expect(!status.enabled && status.consentVersion == "pebble.telemetry.consent/1" && status.installID == nil)
        #expect(status.notice == "Pebble can keep a private usage log on this Mac.")
        #expect(status.events == 2 && status.dropped == 0 && status.expired == 0 && status.refused == 1)
        #expect(status.maxEvents == 1000 && status.maxKilobytes == 256 && status.retentionDays == 30)
        #expect(status.fields.map(\.kind) == ["error", "run settled"])
        #expect(status.fields.last?.names == ["wall ms log2", "steps"])
        #expect(fake.calls("telemetry_get").last?.params == [:])
        // An answer that doesn't say whether it is on is not a status.
        #expect(TelemetryStatus(json: ["consent_text": "x"]) == nil)
        #expect(TelemetryStatus(json: ["enabled": .null])?.enabled == false)
    }

    @Test func turningTelemetryOnSendsTheNoticesVersionAndOffDeletesTheLog() async throws {
        let (store, fake) = await settingsStore { method, params in
            method == "telemetry_set" ? ["enabled": params["enabled"] ?? .null, "install_id": "abc"] : nil
        }
        let shown = TelemetryStatus(consentVersion: "pebble.telemetry.consent/1", notice: "…")
        #expect(try await store.turnOnTelemetry(readNotice: shown).enabled)
        #expect(try await !store.turnOffTelemetry().enabled)
        let calls = fake.calls("telemetry_set")
        #expect(
            calls.map(\.params)
                == [["enabled": true, "consent_version": "pebble.telemetry.consent/1"], ["enabled": false]])
        #expect(calls.allSatisfy { !$0.elevated })
        // Without the notice's version there is nothing to agree to: no call.
        await #expect(throws: RemoteCallError.self) { try await store.turnOnTelemetry(readNotice: TelemetryStatus()) }
        #expect(fake.calls("telemetry_set").count == 2)
    }

    @Test func theDemosTelemetryTurnsOnOnlyWithTheNoticeShownAndOffDeletesIt() async throws {
        let store = await demoStore()
        let off = try await store.telemetry()
        #expect(!off.enabled && off.consentVersion == "pebble.telemetry.consent/1")
        #expect(off.notice.hasPrefix("Pebble can keep"))
        var stale = off
        stale.consentVersion = "pebble.telemetry.consent/0"
        await #expect(throws: RemoteCallError.self) { try await store.turnOnTelemetry(readNotice: stale) }
        #expect(store.notice?.message == "Review the current telemetry notice before turning it on.")
        let on = try await store.turnOnTelemetry(readNotice: off)
        #expect(on.enabled && on.consentedAt == Fixture.t0 && on.installID?.count == 32)
        #expect(try await store.telemetry().enabled)
        #expect(try await !store.turnOffTelemetry().enabled)
        #expect(try await store.telemetry().installID == nil)
    }

    // MARK: - Settings › Permissions: Pebble's Shell (SP-14)

    @Test func shellGrantsAreReadSitesFirstAndEachRemovalAsksFaceID() async throws {
        let (store, fake) = await settingsStore { method, params in
            switch method {
            case "shell_grants":
                return [
                    "hosts": ["b.example": "always", "a.example": "session", "": "always"],
                    "folders": ["/Users/me/out": "always", "/Users/me/tmp": 4], "other": ["x": "always"],
                ]
            case "shell_grant_remove": return ["hosts": ["b.example": "always"], "folders": [:]]
            default: return nil
            }
        }
        let grants = try await store.shellGrants()
        #expect(grants.map(\.value) == ["a.example", "b.example", "/Users/me/out", "/Users/me/tmp"])
        #expect(grants.map(\.kind) == [.site, .site, .folder, .folder])
        #expect(grants.map(\.always) == [false, true, true, false], "anything but always lasts until Pebble quits")
        #expect(fake.calls("shell_grants").last?.params == [:])
        let left = try await store.removeShellGrant(grants[0])
        #expect(left == [ShellGrant(kind: .site, value: "b.example", always: true)])
        let call = try #require(fake.calls("shell_grant_remove").last)
        #expect(call.elevated && call.params == ["kind": "hosts", "value": "a.example"])
        #expect(call.reason == "Remove \u{201C}a.example\u{201D} from Pebble\u{2019}s Shell")
    }

    @Test func theDemosShellGrantsAreRemovedOneAtATime() async throws {
        let store = await demoStore()
        let grants = try await store.shellGrants()
        #expect(grants.map(\.value) == ["api.github.com", "registry.npmjs.org", "/Users/you/Projects/pebble-web/dist"])
        let site = try #require(grants.first)
        let left = try await store.removeShellGrant(site)
        #expect(left.count == 2 && !left.contains(site))
        #expect(try await store.shellGrants() == left)
    }

    // MARK: - Settings › General: notification delivery per schedule (SG-13)

    @Test func deliveryIsReadAsTheMacsBlockAndMutingSendsPebblesParams() async throws {
        let (store, fake) = await settingsStore { method, _ in
            guard method == "notification_status" else { return nil }
            return [
                "settings": ["enabled": true, "preview": "body"], "quiet_now": true,
                "outbox": ["pending": 1, "delivered": 4.5, "suppressed": "2", "failed": 3], "deferred": 2,
                "last_failure": ["reason": "denied", "at": "2026-10-31T09:00:00Z"],
                "jobs": [
                    [
                        "job_id": "j1", "chat_id": "c1", "label": "Weekly commit summary", "state": "active",
                        "muted": false,
                    ],
                    ["job_id": "j2", "label": "Lisbon weather", "muted": true], ["job_id": "j3", "label": "No state"],
                ],
            ]
        }
        let delivery = try await store.notificationDelivery()
        #expect(delivery.waiting == 1 && delivery.shown == 0 && delivery.notShown == 0 && delivery.failed == 3)
        #expect(delivery.heldForQuietHours == 2 && delivery.quietHoursNow && delivery.lastProblem == "denied")
        #expect(delivery.schedules.map(\.jobID) == ["j1", "j2"] && delivery.schedules.map(\.muted) == [false, true])
        #expect(store.notificationSettings?["preview"] == "body", "the settings it carries are kept")
        #expect(fake.calls("notification_status").last?.params == [:])
        #expect(NotificationDelivery(json: ["last_failure": .null]).lastProblem == nil)
        #expect(NotificationDelivery(json: ["last_failure": ["reason": 5]]).lastProblem == "", "a reason not in words")
        let schedule = try #require(delivery.schedules.first)
        try await store.muteBanners(of: schedule, true)
        let call = try #require(fake.calls("notification_mute").last)
        #expect(call.params == ["job_id": "j1", "muted": true] && !call.elevated)
        // Face ID only if a bridge elevates it; then it names the Mac's button and the schedule.
        let reason = SettingsWords.muteReason("Weekly commit summary", muted: true)
        #expect(reason == "Mute banners for Weekly commit summary")
    }

    @Test func theDemosSchedulesBannersAreMutedAndBackOn() async throws {
        let store = await demoStore()
        let delivery = try await store.notificationDelivery()
        #expect(delivery.schedules.count == 2 && delivery.schedules.allSatisfy { !$0.muted } && delivery.shown == 4)
        let first = try #require(delivery.schedules.first)
        try await store.muteBanners(of: first, true)
        #expect(try await store.notificationDelivery().schedules.first?.muted == true)
        try await store.muteBanners(of: first, false)
        #expect(try await store.notificationDelivery().schedules.first?.muted == false)
        let gone = NotificationDelivery.Schedule(jobID: "job-gone", label: "Gone", muted: false)
        await #expect(throws: RemoteCallError.self) { try await store.muteBanners(of: gone, true) }
        #expect(store.notice?.message == "Job not found.")
    }

    // MARK: - Settings › Models: a model file's Rest model and Load now (SM-10)

    /// Pebble's state with `model` as the model in use.
    static func state(model: JSONValue) -> StateDTO? {
        guard case .object(var state) = Fixture.stateJSON() else { return nil }
        state["model"] = model
        return StateDTO(json: .object(state))
    }

    @Test func onlyAConfiguredModelFileInUseOffersRestAndLoad() throws {
        var world = PebbleWorld()
        let file: JSONValue = ["kind": "gguf", "configured": true, "state": "unloaded", "name": "qwen3.5-9b"]
        _ = world.load(try #require(Self.state(model: file)))
        #expect(world.overview()?.localModelState == "unloaded")
        // Pebble's `model` events move it: loading, then ready.
        _ = world.apply(Fixture.event("model", ["kind": "gguf", "configured": true, "state": "loading"], seq: 2))
        #expect(world.overview()?.localModelState == "loading")
        _ = world.apply(Fixture.event("model", ["kind": "gguf", "configured": true, "state": "ready"], seq: 3))
        #expect(world.overview()?.localModelState == "ready")
        _ = world.load(try #require(Self.state(model: ["kind": "gguf", "configured": false, "state": "unloaded"])))
        #expect(world.overview()?.localModelState == nil, "no file chosen yet: the Mac shows no button")
        _ = world.load(try #require(Self.state(model: ["kind": "chatgpt", "configured": true, "state": "ready"])))
        #expect(world.overview()?.localModelState == nil, "a cloud model can't be rested")
    }

    @Test func loadAndRestSendWhatTheMacSends() async throws {
        let (store, fake) = await settingsStore()
        try await store.loadLocalModel()
        try await store.restLocalModel()
        #expect(fake.calls("model_load").map(\.params) == [[:]] && fake.calls("model_unload").map(\.params) == [[:]])
        #expect((fake.calls("model_load") + fake.calls("model_unload")).allSatisfy { !$0.elevated })
    }

    @Test func theDemosModelFileLoadsAndRestsButNotWhileATaskRuns() async throws {
        let store = await demoStore()
        #expect(await eventually { store.isPebbleWorking })
        await #expect(throws: RemoteCallError.self) { try await store.restLocalModel() }
        #expect(store.notice?.message == "Stop the current task before unloading the model.")
        try await store.stop(chat: DemoData.loginChat)
        #expect(await eventually { !store.isPebbleWorking })
        #expect(store.pebble?.localModelState == nil, "the demo starts on ChatGPT")
        try await store.selectModel("default-local")
        #expect(await eventually { store.pebble?.localModelState == "unloaded" })
        try await store.loadLocalModel()
        #expect(store.pebble?.localModelState == "ready")
        try await store.restLocalModel()
        #expect(store.pebble?.localModelState == "unloaded")
    }
}

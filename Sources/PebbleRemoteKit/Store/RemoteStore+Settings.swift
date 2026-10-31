import Foundation
import PebbleProtocol

// Lane S (2026-10-31): Settings controls that were "On your Mac" rows (docs/parity/MAC_INVENTORY.md). Calls and params
// are Pebble's own (read-only Pebble checkout: app.py's dispatcher and the modules behind it; the Vue files that call
// them). Reads that report go through `answer`; calls that act go through `act`, which asks for Face ID where the
// bridge's `welcome.elevated` lists the method, or when the bridge answers `proof_required`. None of these is a read
// the bridge lets through before the unlock (contract C1), so the client asks for the unlock itself when one is needed.

extension RemoteStore {
    // MARK: Settings › Memory (SY-12, SY-13, SY-16, SY-19)

    /// The learning candidates Pebble's Memory settings list (`memory_candidates`): waiting for evidence, disagreeing
    /// with a saved memory, or not saved. Settings on the phone belong to no conversation, so it asks for every
    /// conversation's, as Pebble's window does when none is open.
    public func memoryCandidates() async throws -> [MemoryCandidate] {
        let result = try await answer("memory_candidates", [:])
        return (result.array ?? []).compactMap(MemoryCandidate.init(json:))
            .filter { MemoryCandidate.shownStates.contains($0.status) }
    }

    /// "Use this value" (`useValue`) or "Keep current" for a candidate that disagrees with a saved memory
    /// (`memory_resolve {candidate_id, accept}`). Pebble refuses while a task runs.
    public func decide(_ candidate: MemoryCandidate, useValue: Bool) async throws {
        _ = try await act(
            "memory_resolve", ["candidate_id": .string(candidate.id), "accept": .bool(useValue)],
            reason: SettingsWords.decideCandidateReason(useValue: useValue))
        requestState()  // the layers' counts
    }

    /// "Check waiting memories now" (`memory_maintain`): Pebble's memory upkeep runs at once. Refused while a task
    /// runs.
    public func checkWaitingMemories() async throws {
        _ = try await act("memory_maintain", [:], reason: SettingsWords.checkMemoriesReason)
        requestState()
    }

    /// Saves a memory by hand (`memory_save {kind, content, scope, expires, id}`), as Pebble's "Save memory" does: not
    /// in the working or past-experience layers, at most 4,000 characters, and an expiry for time-sensitive ones (null
    /// for the others, as the Mac sends). A project memory names the project's newest conversation, as Pebble's window
    /// names the open one; Pebble keeps the memory with the project's folder, not with that conversation.
    public func saveMemory(_ text: String, in layer: String, recall: MemoryRecall, expires: Date?) async throws {
        var params: [String: JSONValue] = [
            "kind": .string(layer), "content": .string(text), "scope": "global",
            "expires": expires.map { JSONValue.double($0.timeIntervalSince1970) } ?? .null,
        ]
        if case .project(let project) = recall {
            guard let chat = newestChat(in: project.path) else {
                throw settingsRefusal(SettingsWords.connectProjectFirst)
            }
            params["scope"] = "project"
            params["id"] = .string(chat)
        }
        _ = try await act("memory_save", .object(params), reason: SettingsWords.saveMemoryReason)
        requestState()
    }

    /// "Forget all memories" (`memory_clear`): every saved memory and task checkpoint, for good; conversations stay.
    /// Face ID (contract 3.6); Pebble refuses while a task runs.
    public func forgetAllMemories() async throws {
        _ = try await act("memory_clear", [:], reason: SettingsWords.forgetAllMemoriesReason)
        requestState()
    }

    // MARK: Settings › Skills & connectors (SK-04, SK-05, SK-06, SK-09)

    /// Pebble's skills, connectors and hooks, oldest first (`extensions`), with what each one's Review shows.
    public func extensions() async throws -> [ExtensionItem] {
        let result = try await answer("extensions", [:])
        return (result.array ?? []).compactMap(ExtensionItem.init(json:))
    }

    /// One page of a skill's reference file, from the skill's pinned snapshot (`skill_inspect {id, digest, reference,
    /// offset}`), as the Mac's "View text" and "Load next page" read it. Pebble checks the file is in that snapshot.
    public func skillText(_ item: ExtensionItem, file: String, from offset: Int = 0) async throws -> SkillTextPage {
        guard let snapshot = item.skill?.snapshot else { throw report(unreadable()) }
        let params: JSONValue = [
            "id": .string(item.id), "digest": .string(snapshot), "reference": .string(file), "offset": .int(offset),
        ]
        let result = try await answer("skill_inspect", params)
        guard let page = SkillTextPage(json: result), page.path == file else { throw report(unreadable()) }
        return page
    }

    /// Enable or Disable a skill, connector or hook (`extension_toggle {id, enabled}`). More reach: Face ID (contract
    /// 3.6). Pebble refuses while a task runs, and a connector Permissions doesn't allow.
    public func setExtension(_ item: ExtensionItem, enabled: Bool) async throws {
        _ = try await act(
            "extension_toggle", ["id": .string(item.id), "enabled": .bool(enabled)],
            reason: SettingsWords.extensionReason(item.name, enabled: enabled))
    }

    // MARK: Settings › Data & storage (SD-11, SD-12, SD-14, SD-15)

    /// What Pebble's Data & storage page says about the person's files (`storage_summary`; Pebble measures its folders
    /// for it, about 3 s). Recently deleted, which it lists too, is kept current for Chats.
    public func storageOverview() async throws -> StorageOverview {
        let overview = StorageOverview(json: try await answer("storage_summary", [:]))
        if trashed != overview.recentlyDeleted { trashed = overview.recentlyDeleted }
        return overview
    }

    /// "Update copies now" (`storage_refresh`): Pebble's Documents copy pass runs at once and acts on deletions that
    /// wait; Pebble answers with its page as it is then.
    public func updateCopies() async throws -> StorageOverview {
        let result = try await act("storage_refresh", [:], reason: SettingsWords.updateCopiesReason)
        let overview = StorageOverview(json: result)
        if trashed != overview.recentlyDeleted { trashed = overview.recentlyDeleted }
        requestState()
        return overview
    }

    /// "Delete all conversations…" (`storage_trash_all {confirm: true}`, after the person confirmed): every
    /// conversation moves to Recently deleted, but one with a running task or an active schedule. Face ID (contract
    /// 3.6).
    public func moveAllToRecentlyDeleted() async throws -> ConversationsRemoved {
        let result = try await act("storage_trash_all", ["confirm": true], reason: SettingsWords.trashAllReason)
        await loadTrash()
        // Pebble says only that Recently deleted changed; a conversation open here leaves the lists as `trash` does.
        var change = WorldChange(needsState: true)
        for chat in trashed { change.formUnion(world.markTrashed(chat: chat.id, true)) }
        publish(change)
        return ConversationsRemoved(count: max(0, result["moved"]?.int ?? 0), kept: result["kept"]?.array?.count ?? 0)
    }

    /// "Delete all now…" (`storage_purge_all {confirm: true}`, after the person confirmed): every conversation in
    /// Recently deleted, for good. Face ID (contract 3.6).
    public func deleteAllForGood() async throws -> ConversationsRemoved {
        let before = trashed.map(\.id)
        let result = try await act("storage_purge_all", ["confirm": true], reason: SettingsWords.purgeAllReason)
        await loadTrash()
        let remaining = Set(trashed.map(\.id))
        for chat in before where !remaining.contains(chat) {
            transcripts[chat] = nil
            publish(world.forget(chat: chat))
        }
        requestState()
        return ConversationsRemoved(count: max(0, result["deleted"]?.int ?? 0), kept: result["kept"]?.array?.count ?? 0)
    }

    // MARK: Settings › Privacy & Stealth: usage telemetry (SS-03, SS-06)

    /// Pebble's usage log: whether it is on, its notice and limits (`telemetry_get`).
    public func telemetry() async throws -> TelemetryStatus {
        let result = try await answer("telemetry_get", [:])
        guard let status = TelemetryStatus(json: result) else { throw report(unreadable()) }
        return status
    }

    /// "Turn on", after the person ticked "I have read this notice…": `telemetry_set {enabled: true, consent_version}`
    /// with the version of the notice shown, as the Mac sends it (Pebble refuses any other version).
    public func turnOnTelemetry(readNotice status: TelemetryStatus) async throws -> TelemetryStatus {
        guard !status.consentVersion.isEmpty else { throw report(unreadable()) }
        let params: JSONValue = ["enabled": true, "consent_version": .string(status.consentVersion)]
        let result = try await act("telemetry_set", params, reason: SettingsWords.telemetryOnReason)
        guard let next = TelemetryStatus(json: result) else { throw report(unreadable()) }
        return next
    }

    /// "Turn off and delete the log": `telemetry_set {enabled: false}`; Pebble deletes the log.
    public func turnOffTelemetry() async throws -> TelemetryStatus {
        let result = try await act("telemetry_set", ["enabled": false], reason: SettingsWords.telemetryOffReason)
        guard let next = TelemetryStatus(json: result) else { throw report(unreadable()) }
        return next
    }

    // MARK: Settings › Permissions: Pebble's Shell (SP-14)

    /// The websites and folders Pebble's Shell may use without asking (`shell_grants`).
    public func shellGrants() async throws -> [ShellGrant] {
        ShellGrant.list(json: try await answer("shell_grants", [:]))
    }

    /// "Remove" one (`shell_grant_remove {kind, value}`); Pebble answers with what is left. It takes reach away, but
    /// the bridge asks for Face ID for every change to the Shell's grants (contract 3.6).
    public func removeShellGrant(_ grant: ShellGrant) async throws -> [ShellGrant] {
        let params: JSONValue = ["kind": .string(grant.kind.rawValue), "value": .string(grant.value)]
        let result = try await act("shell_grant_remove", params, reason: SettingsWords.removeGrantReason(grant.value))
        return ShellGrant.list(json: result)
    }

    // MARK: Settings › General: notification delivery per schedule (SG-13)

    /// What became of the Mac's banners, and each schedule's banners (`notification_status`). The settings it carries
    /// keep Notifications on Your Mac current too.
    public func notificationDelivery() async throws -> NotificationDelivery {
        let status = try await answer("notification_status", [:])
        if let settings = status["settings"], settings.object != nil, notificationSettings != settings {
            notificationSettings = settings
        }
        return NotificationDelivery(json: status)
    }

    /// "Mute" or "Unmute" one schedule's banners (`notification_mute {job_id, muted}`); its updates stay in Pebble.
    public func muteBanners(of schedule: NotificationDelivery.Schedule, _ muted: Bool) async throws {
        _ = try await act(
            "notification_mute", ["job_id": .string(schedule.jobID), "muted": .bool(muted)],
            reason: SettingsWords.muteReason(schedule.label, muted: muted))
    }

    // MARK: Settings › Models: a model file's Rest model and Load now (SM-10)

    /// "Load now" (`model_load`): Pebble starts the model file in use; its `model` events say "loading", then "ready".
    /// Returns once the store has read Pebble's state.
    public func loadLocalModel() async throws {
        _ = try await act("model_load", [:], reason: SettingsWords.loadModelReason)
        await refreshState()
    }

    /// "Rest model" (`model_unload`): Pebble stops the model file and frees its memory. Refused while a task runs.
    public func restLocalModel() async throws {
        _ = try await act("model_unload", [:], reason: SettingsWords.restModelReason)
        await refreshState()
    }

    // MARK: Helpers

    /// The newest conversation, not in Recently deleted, whose project is `folder`.
    func newestChat(in folder: String) -> ChatID? {
        world.chats.values.filter { !$0.trashed && $0.workspace == folder }
            .sorted { ($0.updated ?? .distantPast, $0.id) > ($1.updated ?? .distantPast, $1.id) }
            .first?.id
    }

    /// A refusal the store writes itself, shown once as `notice`.
    func settingsRefusal(_ words: String) -> RemoteCallError {
        let failure = PersonFacingError(message: words)
        notice = failure
        return .refused(failure)
    }
}

/// What Face ID says when a Settings control asks for it, and the few sentences the store writes itself (Kit can't read
/// PebbleDesign's copy). Each names the action as Pebble's button does.
public enum SettingsWords {
    // Settings › Memory
    public static func decideCandidateReason(useValue: Bool) -> String { useValue ? "Use this value" : "Keep current" }
    public static let checkMemoriesReason = "Check waiting memories now"
    public static let saveMemoryReason = "Save memory"
    public static let forgetAllMemoriesReason = "Forget all memories"
    /// Pebble's own words (app.py `memory_save`) when a project memory has no conversation in the project to name.
    public static let connectProjectFirst = "Connect a project before saving project memory."

    // Settings › Data & storage: the Mac's buttons.
    public static let updateCopiesReason = "Update copies now"
    public static let trashAllReason = "Move all to Recently deleted"
    public static let purgeAllReason = "Delete all for good"

    // Settings › Privacy & Stealth: the Mac's buttons.
    public static let telemetryOnReason = "Turn on usage telemetry"
    public static let telemetryOffReason = "Turn off and delete the log"

    // Settings › Permissions: the Mac's button, then the site or folder.
    public static func removeGrantReason(_ value: String) -> String {
        "Remove \u{201C}\(StoreWords.detail(value))\u{201D} from Pebble\u{2019}s Shell"
    }

    // Settings › General: the Mac's button label, then the schedule.
    public static func muteReason(_ label: String, muted: Bool) -> String {
        (muted ? "Mute banners for " : "Unmute banners for ") + StoreWords.detail(label)
    }

    // Settings › Models: the Mac's buttons.
    public static let loadModelReason = "Load now"
    public static let restModelReason = "Rest model"

    // Settings › Skills & connectors: the Mac's button, then the name Pebble lists.
    public static func extensionReason(_ name: String, enabled: Bool) -> String {
        let shown = StoreWords.detail(name)
        return (enabled ? "Enable" : "Disable") + (shown.isEmpty ? "" : " \u{201C}\(shown)\u{201D}")
    }
}

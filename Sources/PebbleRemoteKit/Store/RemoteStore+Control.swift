import Foundation
import PebbleProtocol

// The Control tab, Settings and the conversation details (contract v0.2 P1; R2 widened: the phone controls what the
// Mac's main window can). Calls and params follow Pebble's own windows; failures become `notice` and are rethrown,
// as everywhere in the store. Every call that is not a read also needs the bridge's unlock (contract C1), which the
// client asks Face ID for on its own.

extension RemoteStore {
    // MARK: Conversations in a project

    /// Starts a new conversation in Companion (nil) or a project (`new_chat {workspace}`), and sends the first message,
    /// if any. A folder no conversation uses yet asks for Face ID (proposal v0.5; RemoteStore+Projects `makeChat`). A
    /// screen that should make nothing on the Mac before the first message uses a draft (`newDraft(in:)`,
    /// `send(_:from:)`).
    public func newChat(firstMessage: String?, in project: ProjectRef?) async throws -> ChatID {
        let id = try await makeChat(in: project)
        if let firstMessage, !firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await send(firstMessage, in: id)
        }
        return id
    }

    // MARK: Models

    /// Uses another model profile (`model_select {profile_id}`). Pebble refuses while a task runs. Returns once the
    /// store has read Pebble's new state, so the screens show only the model Pebble confirmed.
    public func selectModel(_ id: String) async throws {
        try await perform("model_select", ["profile_id": .string(id)])
        await refreshState()
    }

    /// Changes the effort of the model in use (`model_effort {effort}`), one of the efforts it offers.
    public func setEffort(_ effort: String) async throws {
        try await perform("model_effort", ["effort": .string(effort)])
        await refreshState()
    }

    // MARK: Settings (App.setting in Pebble: every key takes its whole value)

    /// Sets one of Pebble's settings. A key the bridge lists as `setting:<key>` in `welcome.elevated` asks for Face ID
    /// (an elevated call); a bridge that lists none elevates `permissions` (contract 3.6), which Pebble also refuses
    /// while a task runs. Prefer the typed setters below, which send the whole value Pebble expects. Returns once the
    /// store has read Pebble's new state.
    public func setSetting(_ key: String, to value: JSONValue) async throws {
        let params: JSONValue = ["key": .string(key), "value": value]
        do {
            if settingNeedsProof(key) {
                let reason = key == "permissions" ? StoreWords.permissionsReason : StoreWords.settingReason
                _ = try await client.callElevated("setting", params, reason: reason)
            } else {
                _ = try await client.call("setting", params)
            }
        } catch {
            throw report(error)
        }
        await refreshState()
    }

    /// Whether a setting's key needs Face ID (contract v0.3 item 5: `welcome.elevated` may name keys).
    public func settingNeedsProof(_ key: String) -> Bool {
        let keys = (bridge?.elevated ?? []).filter { $0.hasPrefix("setting:") }.map { String($0.dropFirst("setting:".count)) }
        return keys.isEmpty ? key == "permissions" : keys.contains(key)
    }

    /// "system", "light" or "dark".
    public func setTheme(_ theme: String) async throws { try await setSetting("theme", to: .string(theme)) }
    public func setReducedMotion(_ on: Bool) async throws { try await setSetting("reduced_motion", to: .bool(on)) }
    public func setMemoryEnabled(_ on: Bool) async throws { try await setSetting("memory_enabled", to: .bool(on)) }

    /// Pebble's six memory layers (memory.KINDS), in its order.
    public nonisolated static let memoryLayerNames = ["working", "episodic", "semantic", "procedural", "temporal", "profile"]

    /// One memory layer on or off; Pebble takes all six together (each on unless Pebble said otherwise).
    public func setMemoryLayer(_ layer: String, on: Bool) async throws {
        var layers = Dictionary(uniqueKeysWithValues: Self.memoryLayerNames.map { ($0, true) })
        layers.merge(settings?.memoryLayers ?? [:]) { _, reported in reported }
        layers[layer] = on
        try await setSetting("memory_layers", to: .object(layers.mapValues(JSONValue.bool)))
    }

    /// One permission group on or off (files, edits, tests, apps, web, terminal, plugins, views, screen, capture).
    /// Asks for Face ID: Pebble takes the whole permissions object.
    public func setToolSwitch(_ tool: String, on: Bool) async throws {
        guard case .object(var permissions)? = world.settings?.permissions, case .object(var tools)? = permissions["tools"]
        else {
            let failure = PersonFacingError(message: StoreWords.settingsNotRead, code: StoreWords.Code.notConnected)
            notice = failure
            throw RemoteCallError.refused(failure)
        }
        tools[tool] = .bool(on)
        permissions["tools"] = .object(tools)
        try await setSetting("permissions", to: .object(permissions))
    }

    /// The companion's presentation switches, whole: `{pointer, reactions, status_words, ui_guidance}`.
    public func setCompanion(_ value: JSONValue) async throws { try await setSetting("companion", to: value) }
    /// The Git decisions, whole, as Pebble reports them in `settings.gitDecisions`.
    public func setGitDecisions(_ value: JSONValue) async throws { try await setSetting("git_decisions", to: value) }
    /// Pebble's notification settings, whole.
    public func setNotifications(_ value: JSONValue) async throws { try await setSetting("notifications", to: value) }

    // MARK: The Mac

    /// A picture of the Mac's screens (`remote.screenshot`, contract C3): one display, or all of them. The Mac shows
    /// a notice each time; nothing is kept on either side.
    public func screenshot(display: Int? = nil) async throws -> MacScreenshot {
        let result: JSONValue
        do {
            result = try await client.call("remote.screenshot", ["display": display.map(JSONValue.int) ?? .null])
        } catch {
            throw report(error)
        }
        guard let picture = MacScreenshot(json: result) else { throw unreadable() }
        return picture
    }

    /// Removes a phone from the Mac's paired devices. Removing this phone ends its connection, as on the Mac, and needs
    /// only the unlock. Removing another phone asks for Face ID: Pebble's bridge answers `proof_required` without one
    /// (security review X-8), which `welcome.elevated` cannot say, so it goes elevated at once, as `setWorkspace` does
    /// for a new folder; a bridge that wants a proof for this phone too gets one (`act` retries on `proof_required`).
    public func revokeDevice(_ device: MacDevice) async throws {
        _ = try await act(
            "remote.revoke_device", ["device_id": .string(device.id)], reason: StoreWords.removePhoneReason(device.name),
            elevate: !device.isCurrent)
        devices.removeAll { $0.id == device.id }
    }

}

extension RemoteStore {
    // MARK: The unlock (contract C1)

    /// Acting on the Mac is unlocked now (by the store's clock).
    public var isUnlocked: Bool { unlockedUntil.map { $0 > clock() } ?? false }

    /// Asks for Face ID and unlocks acting on the Mac for a while (the bridge's `unlock_seconds`, 15 minutes unless the
    /// person changed it on the Mac). The app calls it when it opens; the person cancelling Face ID is not a failure.
    public func unlock() async throws {
        do {
            try await client.unlock(reason: StoreWords.unlockReason)
        } catch {
            throw report(error)
        }
    }
}

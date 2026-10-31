import Foundation
import PebbleProtocol

// Lane S: the demo's answers for the Settings controls that were "On your Mac" rows, with Pebble's own refusal words
// (read-only Pebble checkout: app.py memory_save, memory_maintain, memory_resolve, memory_clear; memory.py `put`;
// memory_learning.py `resolve`). State lives in `settingsDemo` (DemoSettings) and in the demo's memory (DemoMemory).

extension DemoClient {
    /// The answer to one of these methods, or nil when `method` is not one of them.
    func settingsAnswer(_ method: String, _ params: JSONValue, proven: Bool) throws -> JSONValue? {
        switch method {
        case "memory_candidates": return settingsDemo.candidatesJSON(now: now())
        case "memory_resolve": return try resolveCandidate(params)
        case "memory_maintain": return try maintainMemory()
        case "memory_save": return try saveMemory(params)
        case "memory_clear": return try clearMemory()
        case "extensions":
            return .array(settingsDemo.extensions.sorted { $0.age > $1.age }.map { $0.json(now: now()) })
        case "skill_inspect": return try inspectSkill(params)
        case "extension_toggle": return try toggleExtension(params)
        case "storage_refresh":
            settingsDemo.refreshCopies()
            return storageSummary()
        case "storage_trash_all": return try trashAll(params)
        case "storage_purge_all": return try purgeAll(params)
        case "telemetry_get": return settingsDemo.telemetryJSON()
        case "telemetry_set": return try setTelemetry(params)
        case "notification_status": return try deliveryStatus(params)
        case "notification_mute": return try muteBanners(params)
        case "model_load", "model_unload": return try loadOrRestModel(load: method == "model_load")
        case "shell_grants": return settingsDemo.shellGrantsJSON()
        case "shell_grant_remove":
            // companion_tools.py `remove_grant`: one that isn't there is no error; Pebble answers with what is left.
            guard let kind = params["kind"]?.string, ["hosts", "folders"].contains(kind) else {
                throw refusal("Choose hosts or folders.")
            }
            settingsDemo.shellGrants[kind]?[params["value"]?.string ?? ""] = nil
            return settingsDemo.shellGrantsJSON()
        default: return nil
        }
    }

    // MARK: Settings › Memory

    private var taskRunning: Bool { activeRun != nil }

    /// `memory_resolve {candidate_id, accept}`: Use this value saves the proposal; Keep current rejects it.
    private func resolveCandidate(_ params: JSONValue) throws -> JSONValue {
        if taskRunning { throw refusal("Wait for the current task before resolving a memory conflict.") }
        guard let accept = params["accept"]?.bool else {
            throw refusal("Choose whether to accept the supported conflicting record.")
        }
        guard let id = params["candidate_id"]?.string,
            let index = settingsDemo.candidates.firstIndex(where: { $0.id == id && $0.status == "conflict" })
        else { throw refusal("No conflicting candidate found.") }
        guard accept else {
            settingsDemo.candidates[index].status = "rejected"
            settingsDemo.candidates[index].reason = "native_reject"
            return ["status": "rejected"]
        }
        return ["processed": 1, "outcomes": [promote(at: index)], "authorization": "none"]
    }

    /// `memory_maintain`: the test run behind the waiting recipe has finished, so upkeep saves it.
    private func maintainMemory() throws -> JSONValue {
        if taskRunning { throw refusal("Wait for the current task before running manual maintenance.") }
        guard settings["memory_enabled"]?.bool ?? true else { return ["processed": 0, "status": "disabled"] }
        let waiting = settingsDemo.candidates.indices.filter { settingsDemo.candidates[$0].status == "pending" }
        let outcomes = waiting.map { promote(at: $0) }
        return ["processed": .int(outcomes.count), "outcomes": .array(outcomes), "authorization": "none"]
    }

    /// A candidate becomes a memory in its layer (a test recipe as Pebble stores one).
    private func promote(at index: Int) -> JSONValue {
        let candidate = settingsDemo.candidates[index]
        settingsDemo.candidates[index].status = "promoted"
        settingsDemo.candidates[index].reason = nil
        let recipe = #"{"recipe":"npm run lint","language":"JavaScript"}"#
        let content = candidate.content.isEmpty ? recipe : candidate.content
        memory.memories.append(
            DemoMemory.Memory(
                id: "mem-" + candidate.id, kind: candidate.kind, content: content, scope: candidate.scope,
                chatID: candidate.chatID, origin: "auto-learned", updated: now(),
                evidence: candidate.kind == "procedural" ? "test_recipe" : "human_preference"))
        return [
            "candidate_id": .string(candidate.id), "status": "promoted", "memory_id": .string("mem-" + candidate.id),
        ]
    }

    /// `memory_save {kind, content, id?, scope, expires}`, checked in Pebble's order.
    private func saveMemory(_ params: JSONValue) throws -> JSONValue {
        let kind = params["kind"]?.string ?? ""
        if kind == "working" || kind == "episodic" {
            throw refusal("Task context and experience are recorded from actual conversations.")
        }
        var scope = "global"
        switch params["scope"]?.string ?? "global" {
        case "global": break
        case "project":
            guard let id = params["id"]?.string, let chat = chats.first(where: { $0.id == id }) else {
                throw refusal("Conversation not found.")
            }
            guard let folder = chat.workspace else { throw refusal("Connect a project before saving project memory.") }
            scope = folder
        default: throw refusal("Choose personal or project memory.")
        }
        let expiry = params["expires"]?.double
        if kind == "temporal", expiry == nil { throw refusal("Time-sensitive memories need an expiry date.") }
        guard DemoMemory.kinds.contains(where: { $0.id == kind }), let content = params["content"]?.string,
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, content.count <= 4000
        else { throw refusal("Choose a memory type and enter 1\u{2013}4000 characters.") }
        let layerOn = (settings["memory_enabled"]?.bool ?? true) && (settings["memory_layers"]?[kind]?.bool ?? true)
        guard layerOn else { throw refusal("Memory is off for this layer.") }
        if let expiry, !expiry.isFinite || expiry <= now().timeIntervalSince1970 {
            throw refusal("The expiry must be in the future.")
        }
        settingsDemo.added += 1
        let id = "mem-added-\(settingsDemo.added)"
        memory.memories.append(
            DemoMemory.Memory(
                id: id, kind: kind, content: content, scope: scope, origin: "user", updated: now(),
                expires: expiry.map(Date.init(timeIntervalSince1970:))))
        return .string(id)
    }

    /// `memory_clear`: every memory, checkpoint and candidate.
    private func clearMemory() throws -> JSONValue {
        if taskRunning { throw refusal("Stop the current task before forgetting memories.") }
        memory.memories.removeAll()
        memory.contests = [:]
        settingsDemo.candidates.removeAll()
        return true
    }

    // MARK: Settings › Skills & connectors

    /// `skill_inspect {id, digest, reference, offset, limit}`: a reference file of the skill's pinned snapshot, a page
    /// at a time (skill_bundle.py `load`).
    private func inspectSkill(_ params: JSONValue) throws -> JSONValue {
        guard let item = settingsDemo.extensions.first(where: { $0.id == params["id"]?.string }) else {
            throw refusal("This extension is missing or disabled.")
        }
        guard item.kind == "skill" else { throw refusal("Choose an installed skill snapshot.") }
        if let digest = params["digest"]?.string, digest != DemoSettings.skillSnapshot {
            throw refusal("Skill snapshot changed or is invalid; install a reviewed version.")
        }
        let path = params["reference"]?.string ?? ""
        let listed = (item.config["files"]?.array ?? []).compactMap { $0["path"]?.string }
        guard listed.contains(path), path != item.config["main"]?.string else {
            throw refusal("Choose a reference from this pinned manifest.")
        }
        let offset = params["offset"]?.int ?? 0
        guard (0...96_000).contains(offset) else { throw refusal("Use a bounded character offset.") }
        let limit = params["limit"]?.int ?? 3000
        guard (1...3000).contains(limit) else {
            throw refusal("Use a reference page size from one to 3000 characters.")
        }
        guard let text = DemoSettings.skillFiles[path] else {
            throw refusal("This binary asset is inspectable by hash; text loading is unavailable.")
        }
        let page = String(text.dropFirst(offset).prefix(limit))
        let end = offset + page.count
        return [
            "id": .string(item.id), "load_kind": "reference", "digest": .string(DemoSettings.skillSnapshot),
            "path": .string(path), "untrusted_source": .string(page), "offset": .int(offset),
            "next_offset": end < text.count ? .int(end) : .null, "complete": .bool(offset == 0 && end == text.count),
            "authorization": "none",
        ]
    }

    /// `extension_toggle {id, enabled}`, refused while a task runs and for a connector Permissions doesn't allow.
    private func toggleExtension(_ params: JSONValue) throws -> JSONValue {
        if taskRunning { throw refusal("Stop the current task before changing extensions.") }
        guard let index = settingsDemo.extensions.firstIndex(where: { $0.id == params["id"]?.string }) else {
            throw refusal("This extension is missing or disabled.")
        }
        guard let enabled = params["enabled"]?.bool else { throw refusal("Enabled must be a boolean.") }
        let pluginsAllowed = settings["permissions"]?["tools"]?["plugins"]?.bool == true
        if enabled, settingsDemo.extensions[index].kind == "plugin", !pluginsAllowed {
            throw refusal("Plugin access is disabled in Permissions.")
        }
        settingsDemo.extensions[index].enabled = enabled
        return true
    }

    // MARK: Settings › Data & storage

    /// `storage_trash_all {confirm}`: every listed conversation moves to Recently deleted, but the one whose task runs.
    private func trashAll(_ params: JSONValue) throws -> JSONValue {
        guard params["confirm"]?.bool == true else { throw refusal("Confirm the deletion first.") }
        var moved = 0
        var kept: [JSONValue] = []
        let at = now()
        for chat in chats where trashedAt[chat.id] == nil && (!chat.messages.isEmpty || !chat.actions.isEmpty) {
            if chat.id == activeChat {
                kept.append(
                    ["chat_id": .string(chat.id), "title": .string(chat.title), "reason": "It is running a task."])
                continue
            }
            trashedAt[chat.id] = at
            moved += 1
        }
        if moved > 0 { settingsDemo.note("Moved \(moved) conversation(s) to Recently deleted.") }
        emit("storage", ["changed": "recently_deleted"])
        return ["moved": .int(moved), "kept": .array(kept)]
    }

    /// `storage_purge_all {confirm}`: every conversation in Recently deleted, for good.
    private func purgeAll(_ params: JSONValue) throws -> JSONValue {
        guard params["confirm"]?.bool == true else { throw refusal("Confirm the deletion first.") }
        let gone = Array(trashedAt.keys)
        for id in gone {
            trashedAt[id] = nil
            chats.removeAll { $0.id == id }
            for (run, record) in runs where record.chatID == id { runs[run] = nil }
            emit("storage", ["changed": "deleted", "chat_id": .string(id), "deleted_artifacts": []])
        }
        if !gone.isEmpty { settingsDemo.note("Deleted \(gone.count) conversation(s) for good.") }
        emit("storage", ["changed": "recently_deleted"])
        return ["deleted": .int(gone.count), "kept": []]
    }

    // MARK: Settings › Privacy & Stealth: usage telemetry

    /// `telemetry_set {enabled, consent_version?}` (app.py `telemetry_set`, telemetry.py `enable`).
    private func setTelemetry(_ params: JSONValue) throws -> JSONValue {
        guard let enabled = params["enabled"]?.bool else { throw refusal("Choose on or off.") }
        if enabled {
            guard params["consent_version"]?.string == DemoSettings.consentVersion else {
                throw refusal("Review the current telemetry notice before turning it on.")
            }
            if settingsDemo.telemetrySince == nil { settingsDemo.telemetrySince = now() }
        } else {
            settingsDemo.telemetrySince = nil
        }
        emit("settings", [:])
        return settingsDemo.telemetryJSON()
    }

    // MARK: Settings › General: notification delivery

    /// `notification_status`: the demo's workflows answer it; each schedule's muted state is kept here.
    private func deliveryStatus(_ params: JSONValue) throws -> JSONValue {
        guard params.object?.isEmpty ?? true else { throw refusal("notification_status accepts no fields.") }
        var titles: [String: String] = [:]
        for chat in chats where trashedAt[chat.id] == nil { titles[chat.id] = chat.title }
        guard case .object(var status) = workflows.notificationStatus(chatTitles: titles) else { return .null }
        status["jobs"] = .array((status["jobs"]?.array ?? []).map { job in
            guard case .object(var row) = job, let id = row["job_id"]?.string else { return job }
            row["muted"] = .bool(settingsDemo.mutedJobs.contains(id))
            return .object(row)
        })
        return .object(status)
    }

    /// `notification_mute {job_id, muted}` (notifications.py `set_mute`).
    private func muteBanners(_ params: JSONValue) throws -> JSONValue {
        guard let id = params["job_id"]?.string, workflows.jobs.contains(where: { $0.id == id }) else {
            throw refusal("Job not found.")
        }
        guard let muted = params["muted"]?.bool else { throw refusal("muted must be true or false.") }
        if muted { settingsDemo.mutedJobs.insert(id) } else { settingsDemo.mutedJobs.remove(id) }
        emit("notification_outbox", [:])
        return ["job_id": .string(id), "muted": .bool(muted)]
    }

    // MARK: Settings › Models: a model file's Rest model and Load now

    /// `model_load` loads the model file when it is the model in use (Pebble's `model` events say loading, then ready);
    /// `model_unload` rests it, refused while a task runs (app.py `unload`). Both answer the model's state.
    private func loadOrRestModel(load: Bool) throws -> JSONValue {
        if load {
            if workflows.profile == "default-local", workflows.localModelState != "ready" {
                workflows.localModelState = "loading"
                emit("model", workflows.modelStatus())
                workflows.localModelState = "ready"
                emit("model", workflows.modelStatus())
            }
        } else {
            if taskRunning { throw refusal("Stop the current task before unloading the model.") }
            workflows.localModelState = "unloaded"
            emit("model", workflows.modelStatus())
        }
        return workflows.modelStatus()
    }
}

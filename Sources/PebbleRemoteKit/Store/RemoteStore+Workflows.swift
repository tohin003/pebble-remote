import Foundation
import PebbleProtocol

// The Control tab's lists and actions (contract v0.2 P1): schedules, Pebble's Toolbox, screen sessions, Recently
// deleted, models and paired phones; photos for a message; a run in detail. Calls and params are Pebble's own
// (read-only Pebble checkout: job_api.py, workshop.py, screen_session.py, data_mirror.py, attachments.py,
// run_activity.py; src/bridge.ts attachBytes). Pebble's lambda routes take exactly their named params.

extension RemoteStore {
    // MARK: Lists

    /// Reads every list the bridge offers: models, paired phones, notification settings, schedules, the Toolbox,
    /// screen sessions. The Control tab calls it on appear and on pull to refresh; events keep read lists current.
    public func loadControlLists() async {
        for list in [ControlList.models, .devices, .schedules, .toolbox, .screenSessions] { await load(list) }
    }

    /// Reads one list (Recently deleted is read only when asked: Pebble measures folders for it, about 3 s).
    public func load(_ list: ControlList) async {
        loadedLists.insert(list)
        switch list {
        case .models: await loadModels()
        case .devices: await loadDevices()
        case .notifications, .schedules: await loadSchedules()
        case .toolbox: await loadToolbox()
        case .screenSessions: await loadScreenSessions()
        case .trash: await loadTrash()
        }
    }

    func loadModels() async {
        guard offers("model_profiles"), let result = try? await client.call("model_profiles", [:]) else { return }
        let current = world.currentModel()
        let list = (result.array ?? []).compactMap(ModelChoice.init(profile:)).map { choice in
            var choice = choice
            if choice.efforts.isEmpty, choice.id == current.profileID { choice.efforts = current.efforts }
            return choice
        }
        if models != list { models = list }
    }

    func loadDevices() async {
        guard offers("remote.devices"), let result = try? await client.call("remote.devices", [:]) else { return }
        let list = (result.array ?? result["devices"]?.array ?? []).compactMap(MacDevice.init(json:))
        if devices != list { devices = list }
    }

    // MARK: Schedules (job_*: every job belongs to a conversation)

    /// The jobs of every conversation that has one (notification_status names them), soonest first.
    func loadSchedules() async {
        guard offers("job_list") else { return }
        var chatIDs: [ChatID] = []
        if offers("notification_status"), let status = try? await client.call("notification_status", [:]) {
            if notificationSettings != status["settings"] { notificationSettings = status["settings"] }
            for job in status["jobs"]?.array ?? [] {
                if let chat = job["chat_id"]?.string, !chatIDs.contains(chat) { chatIDs.append(chat) }
            }
        } else {
            chatIDs = chats.prefix(30).map(\.id)
        }
        var items: [ScheduleItem] = []
        for chat in chatIDs {
            guard let result = try? await client.call("job_list", ["id": .string(chat)]) else { continue }
            items += (result["jobs"]?.array ?? []).compactMap {
                ScheduleItem(json: $0, chatID: chat, chatTitle: world.title(of: chat))
            }
        }
        items.sort { ($0.nextRun ?? .distantFuture, $0.name) < ($1.nextRun ?? .distantFuture, $1.name) }
        if schedules != items { schedules = items }
    }

    public func pauseSchedule(_ item: ScheduleItem) async throws {
        let job = try await answer("job_pause", .object(jobParams(item)))
        keep(job: job, chat: item.chatID)
    }

    /// What resuming would run with, for the person to review: a schedule resumes with Pebble's current settings.
    public func reviewResume(_ item: ScheduleItem) async throws -> ScheduleReview {
        let result = try await answer("job_preview_resume", .object(jobParams(item)))
        guard let fingerprint = result["config_fingerprint"]?.string else { throw unreadable() }
        return ScheduleReview(fingerprint: fingerprint, config: result["config"] ?? .null)
    }

    /// Resumes a paused schedule (or one awaiting review) after `reviewResume`. Asks for Face ID.
    public func resumeSchedule(_ item: ScheduleItem, review: ScheduleReview) async throws {
        var params = jobParams(item)
        params["config_fingerprint"] = .string(review.fingerprint)
        let job = try await answerElevated("job_resume", .object(params), reason: StoreWords.resumeScheduleReason(item.name))
        keep(job: job, chat: item.chatID)
    }

    public func deleteSchedule(_ item: ScheduleItem) async throws {
        _ = try await answer("job_delete", .object(jobParams(item)))
        schedules.removeAll { $0.id == item.id }
    }

    /// What a new schedule would run with and its next times, for the person to review before `createSchedule`.
    /// `limits` is `{max_steps, max_seconds}` or null for Pebble's defaults (64 steps, 900 s).
    public func previewSchedule(
        in chat: ChatID, schedule: ScheduleSpec, catchUp: ScheduleSpec.CatchUp = .latest, limits: JSONValue = .null,
        effort: String? = nil
    ) async throws -> ScheduleReview {
        var params: [String: JSONValue] = ["id": .string(chat), "schedule": schedule.json(catchUp: catchUp), "limits": limits]
        if let effort { params["effort"] = .string(effort) }
        let result = try await answer("job_preview", .object(params))
        guard let fingerprint = result["config_fingerprint"]?.string else { throw unreadable() }
        return ScheduleReview(
            fingerprint: fingerprint, config: result["config"] ?? .null,
            nextTimes: (result["next_times"]?.array ?? []).compactMap { $0.double.map(Date.init(timeIntervalSince1970:)) },
            limits: limits, effort: effort)
    }

    /// Makes a schedule in a conversation after `previewSchedule` (the same limits and effort). Asks for Face ID.
    @discardableResult
    public func createSchedule(
        in chat: ChatID, name: String, task: String, schedule: ScheduleSpec, catchUp: ScheduleSpec.CatchUp = .latest,
        monitor: Bool = false, review: ScheduleReview
    ) async throws -> ScheduleItem {
        var params: [String: JSONValue] = [
            "id": .string(chat), "name": .string(name), "task": .string(task), "schedule": schedule.json(catchUp: catchUp),
            "monitor": .bool(monitor), "limits": review.limits, "config_fingerprint": .string(review.fingerprint),
        ]
        if let effort = review.effort { params["effort"] = .string(effort) }
        let job = try await answerElevated("job_create", .object(params), reason: StoreWords.createScheduleReason(name))
        guard let item = ScheduleItem(json: job, chatID: chat, chatTitle: world.title(of: chat)) else { throw unreadable() }
        keep(job: job, chat: chat)
        return item
    }

    /// The person saw a scheduled job's notice.
    public func acknowledge(_ notice: JobNotice) async throws {
        _ = try await answer("notification_ack", ["id": .string(notice.chatID), "notification_id": .string(notice.id)])
        jobNotices.removeAll { $0.id == notice.id }
        requestState()
    }

    private func jobParams(_ item: ScheduleItem) -> [String: JSONValue] {
        ["id": .string(item.chatID), "job_id": .string(item.id), "revision": .int(item.revision)]
    }

    private func keep(job: JSONValue, chat: ChatID) {
        guard let item = ScheduleItem(json: job, chatID: chat, chatTitle: world.title(of: chat)) else { return }
        if let index = schedules.firstIndex(where: { $0.id == item.id }) { schedules[index] = item } else { schedules.append(item) }
    }

    // MARK: Pebble's Toolbox

    func loadToolbox() async {
        guard offers("toolbox_list"), let listing = try? await client.call("toolbox_list", [:]) else { return }
        showToolbox(listing)
    }

    public func removeTool(_ tool: ToolboxEntry) async throws {
        showToolbox(try await answer("toolbox_remove", ["name": .string(tool.name)]))
    }

    /// Puts back a tool removed in the last ten minutes.
    public func putBack(_ tool: RemovedTool) async throws {
        showToolbox(try await answer("toolbox_undo_remove", ["name": .string(tool.name)]))
    }

    /// Keeps or discards a tool Pebble asked about.
    public func decide(_ decision: ToolboxDecision, keep: Bool) async throws {
        showToolbox(try await answer("toolbox_decide", ["pending_id": .string(decision.id), "keep": .bool(keep)]))
    }

    /// One tool's code and checks.
    public func toolDetail(named name: String) async throws -> ToolDetail {
        guard let detail = ToolDetail(json: try await answer("toolbox_get", ["name": .string(name)])) else { throw unreadable() }
        return detail
    }

    private func showToolbox(_ listing: JSONValue) {
        let tools = (listing["tools"]?.array ?? []).compactMap(ToolboxEntry.init(json:))
        let asked = (listing["pending"]?.array ?? []).compactMap(ToolboxDecision.init(json:))
        let removed = (listing["removed"]?.array ?? []).compactMap(RemovedTool.init(json:))
        if toolbox != tools { toolbox = tools }
        if toolboxDecisions != asked { toolboxDecisions = asked }
        if removedTools != removed { removedTools = removed }
    }

    // MARK: Screen and browser sessions

    /// Live sessions of the conversations that can hold one: a grant lasts at most 30 minutes, so those active in the
    /// last 45, with a live run, or open here (Pebble lists sessions per conversation).
    func loadScreenSessions() async {
        guard offers("screen_sessions") else { return }
        let now = clock()
        var chatIDs = Set(chats.filter { ($0.updated ?? .distantPast) > now.addingTimeInterval(-45 * 60) }.map(\.id))
        chatIDs.formUnion(liveRuns.map(\.chatID))
        chatIDs.formUnion(transcripts.keys)
        var live: [ScreenSession] = []
        for chat in chatIDs.sorted() {
            guard let result = try? await client.call("screen_sessions", ["id": .string(chat)]) else { continue }
            live += (result.array ?? []).compactMap { ScreenSession(json: $0, chatID: chat) }.filter { $0.isLive(at: now) }
        }
        live.sort { ($0.expires ?? .distantFuture, $0.id) < ($1.expires ?? .distantFuture, $1.id) }
        if screenSessions != live { screenSessions = live }
    }

    /// Ends Pebble's access to a window or tab ("End access").
    public func revokeScreenSession(_ session: ScreenSession) async throws {
        _ = try await answer("screen_session_revoke", ["session_id": .string(session.id)])
        screenSessions.removeAll { $0.id == session.id }
    }

    /// The person checked a window Pebble handed back ("Done"): Pebble may use it again.
    public func markScreenSessionDone(_ session: ScreenSession) async throws {
        _ = try await answer("screen_handoff_done", ["session_id": .string(session.id)])
        requestList(.screenSessions)
    }

    // MARK: Recently deleted

    func loadTrash() async {
        guard offers("storage_summary"), let summary = try? await client.call("storage_summary", [:]) else { return }
        let list = (summary["recently_deleted"]?.array ?? []).compactMap(TrashedChat.init(json:))
        if trashed != list { trashed = list }
    }

    /// Moves a conversation to Recently deleted (Pebble deletes it for good after 30 days).
    public func trash(chat: ChatID) async throws {
        _ = try await answer("storage_trash_chat", ["chat_id": .string(chat)])
        publish(world.markTrashed(chat: chat, true))
    }

    public func restore(_ chat: TrashedChat) async throws {
        _ = try await answer("storage_restore_chat", ["chat_id": .string(chat.id)])
        trashed.removeAll { $0.id == chat.id }
        publish(world.markTrashed(chat: chat.id, false))
    }

    /// Deletes a conversation in Recently deleted for good. Asks for Face ID.
    public func purge(_ chat: TrashedChat) async throws {
        _ = try await answerElevated(
            "storage_purge_chat", ["chat_id": .string(chat.id), "confirm": true], reason: StoreWords.purgeReason(chat.title))
        trashed.removeAll { $0.id == chat.id }
        transcripts[chat.id] = nil
        publish(world.forget(chat: chat.id))
    }

    // MARK: Photos and files for the next message

    /// Sends a photo or file to the Mac in Pebble's 72,000-byte pieces (src/bridge.ts attachBytes); it goes with the
    /// conversation's next message that starts a task.
    @discardableResult
    public func attach(_ data: Data, name: String, to chat: ChatID) async throws -> AttachmentRef {
        guard data.count <= 50_000_000 else {
            let failure = PersonFacingError(message: StoreWords.fileTooLarge)
            notice = failure
            throw RemoteCallError.refused(failure)
        }
        let piece = 72_000
        var offset = 0
        var upload: String?
        while true {
            let end = min(offset + piece, data.count)
            let final = end >= data.count
            var params: [String: JSONValue] = [
                "id": .string(chat), "name": .string(name), "data_base64": .string(data[offset..<end].base64EncodedString()),
                "offset": .int(offset), "final": .bool(final),
            ]
            if let upload { params["upload"] = .string(upload) }
            let result = try await answer("attach_bytes", .object(params))
            if final {
                guard let attachment = AttachmentRef(json: result) else { throw unreadable() }
                attachments[chat, default: []].append(attachment)
                return attachment
            }
            guard let token = result["upload"]?.string else { throw unreadable() }
            upload = token
            offset = end
        }
    }

    public func removeAttachment(_ attachment: AttachmentRef, from chat: ChatID) async throws {
        _ = try await answer("remove_source", ["id": .string(chat), "source_id": .string(attachment.id)])
        attachments[chat]?.removeAll { $0.id == attachment.id }
    }

    // MARK: A run in detail

    /// A run's record and what it did, in order (run_activity). The record comes from run_list: run_get also carries
    /// every tool's whole result, up to 8 MB each.
    public func runDetails(_ run: RunID, in chat: ChatID) async throws -> RunDetails {
        var record: LiveRunRecord?
        if offers("run_list"), let rows = try? await client.call("run_list", ["id": .string(chat)]) {
            record = (rows.array ?? []).first { $0["id"]?.string == run }.flatMap(LiveRunRecord.init(json:))
        }
        if record == nil, let row = world.runs[run]?.row {
            let note = PersonNote.filter(row.error)
            record = LiveRunRecord(
                id: row.id, chatID: row.chatID, state: row.state, steps: row.steps, elapsed: row.elapsed,
                note: note.isEmpty ? nil : note, created: row.created, updated: row.updated)
        }
        guard let record else { throw unreadable() }
        let activity = try await answer("run_activity", ["run_id": .string(run), "after": 0])
        let items = (activity["items"]?.array ?? []).compactMap(RunActivityItem.init(json:)).sorted { $0.seq < $1.seq }
        let reasoning = activity["reasoning"]?["text"]?.string
        return RunDetails(run: record, items: items, reasoning: reasoning?.isEmpty == false ? reasoning : nil)
    }

    // MARK: Helpers

    /// A call whose answer the store needs; a failure becomes `notice` and is rethrown.
    func answer(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        do {
            return try await client.call(method, params)
        } catch {
            throw report(error)
        }
    }

    func answerElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        do {
            return try await client.callElevated(method, params, reason: reason)
        } catch {
            throw report(error)
        }
    }
}

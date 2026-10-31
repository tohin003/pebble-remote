import Foundation
import PebbleProtocol

/// The demo Pebble's schedules, Toolbox, screen sessions, notification settings, models and settings, answering with
/// Pebble's own shapes and refusal words (read-only Pebble checkout: job_api.py, jobs.py, workshop.py,
/// screen_session.py, notifications.py, providers.py, app.py `setting()`). DemoClient owns one and delegates to it.
struct DemoWorkflows: Sendable {
    typealias Event = (name: String, data: JSONValue)

    struct Job: Sendable, Hashable {
        var id: String
        var chatID: String
        var name: String
        var task: String
        var schedule: JSONValue
        var state: String
        var revision: Int
        var nextFire: Int?
        var monitor: Bool
        var lastRunState: String?
    }

    struct Tool: Sendable, Hashable {
        var name: String
        var purpose: String
        var keptBy: String
        var keptAt: Double
        var uses: Int
        var code: String
    }

    var jobs: [Job] = []
    var notices: [JSONValue] = []
    var tools: [Tool] = []
    var pending: [JSONValue] = []
    var removed: [(tool: Tool, at: Date)] = []
    var sessions: [String: [JSONValue]] = [:]
    var notifications: JSONValue = [
        "enabled": false,
        "kinds": ["completed": true, "failed": true, "action_needed": true, "monitor_changed": true],
        "preview": "title", "quiet_hours": .null, "replies": true,
    ]
    var profile = "chatgpt"
    /// The model file's state: "unloaded" until Load now (lane S: DemoClient+Settings answers model_load and
    /// model_unload).
    var localModelState = "unloaded"
    var efforts: [String: String] = ["chatgpt": "medium", "default-local": "think"]

    static let fingerprintPrefix = "d3m0"

    init(now: Date) {
        let day = 86_400.0
        jobs = [
            Job(
                id: "job-commits", chatID: DemoData.commitsChat, name: "Weekly commit summary",
                task: "Summarize this week's commits for the changelog.",
                schedule: ["kind": "daily", "time": "09:00", "timezone": "Europe/Lisbon"], state: "active", revision: 3,
                nextFire: Int(now.timeIntervalSince1970 + 0.6 * day), monitor: false, lastRunState: "completed"),
            Job(
                id: "job-weather", chatID: DemoData.weatherChat, name: "Lisbon weather each morning",
                task: "Tell me today's weather in Lisbon.", schedule: ["kind": "interval", "seconds": 86_400],
                state: "paused", revision: 2, nextFire: nil, monitor: true, lastRunState: "completed"),
        ]
        notices = [
            [
                "id": "notice-1", "chat_id": .string(DemoData.commitsChat),
                "title": "Scheduled job \u{201C}Weekly commit summary\u{201D} completed",
                "created": .double(now.timeIntervalSince1970 - 3600),
            ]
        ]
        tools = [
            Tool(
                name: "c_to_f", purpose: "Converts Celsius to Fahrenheit", keptBy: "pebble",
                keptAt: now.timeIntervalSince1970 - 5 * day, uses: 3, code: "def c_to_f(c):\n    return c * 9 / 5 + 32\n"),
            Tool(
                name: "word_count", purpose: "Counts the words in a text", keptBy: "person",
                keptAt: now.timeIntervalSince1970 - 2 * day, uses: 7, code: "def word_count(text):\n    return len(text.split())\n"),
        ]
        pending = [
            [
                "id": "pending-split", "name": "split_bill", "purpose": "Splits a bill between people, with a tip",
                "why": ["it has not been used successfully in this task yet"], "chat_id": .string(DemoData.weatherChat),
            ]
        ]
        sessions = [
            DemoData.emailsChat: [
                [
                    "session_id": "session-notes", "run_id": .string(DemoData.emailsRun), "kind": "app",
                    "target": ["kind": "app", "bundle_id": "com.apple.Notes", "team_id": .null, "window": ["title_sha256": "0f1e", "ax_identifier": .null]],
                    "actions": ["focus", "scroll", "type", "press"], "state": "active", "reason": .null,
                    "expires": .double(now.timeIntervalSince1970 + 12 * 60), "pending": false,
                ]
            ],
            // The window the uncertain step paused: Done lets Pebble use it again (RunPanel's paused windows).
            DemoData.mailChat: [
                [
                    "session_id": .string(DemoData.mailWindow), "run_id": .string(DemoData.mailRun), "kind": "app",
                    "target": ["kind": "app", "bundle_id": "com.apple.mail", "team_id": .null, "window": ["title_sha256": "5a7e", "ax_identifier": .null]],
                    "actions": ["focus", "scroll", "type", "press"], "state": "interrupted",
                    "reason": ["reasons": ["uncertain_outcome"]], "expires": .double(now.timeIntervalSince1970 + 11 * 60),
                    "pending": false,
                ]
            ],
            DemoData.readmeChat: [
                [
                    "session_id": "session-docs", "run_id": .string(DemoData.readmeRun), "kind": "browser",
                    "target": ["kind": "browser", "profile": "pebble", "tab_id": "1001", "origins": ["https://docs.github.com"]],
                    "actions": ["focus", "scroll", "expand", "collapse", "select"], "state": "handoff",
                    "reason": ["reasons": ["login_form"]], "expires": .double(now.timeIntervalSince1970 + 9 * 60), "pending": false,
                ]
            ],
        ]
    }

    // MARK: - Answering

    /// The answer to one of the methods this part simulates (and the events it sends), or nil when it is not one.
    mutating func handle(
        _ method: String, _ params: JSONValue, now: Date, chatTitles: [String: String], taskRunning: Bool,
        settings: inout [String: JSONValue]
    ) throws -> (result: JSONValue, events: [Event])? {
        switch method {
        case "notification_status":
            guard params.object?.isEmpty ?? true else { throw refusal("notification_status accepts no fields.") }
            return (notificationStatus(chatTitles: chatTitles), [])
        case "job_list": return try jobList(params, chatTitles: chatTitles)
        case "job_get": return try jobGet(params, chatTitles: chatTitles)
        case "job_preview": return try jobPreview(params, now: now, chatTitles: chatTitles)
        case "job_create": return try jobCreate(params, now: now, chatTitles: chatTitles)
        case "job_pause": return try jobPause(params, chatTitles: chatTitles)
        case "job_preview_resume": return try jobPreviewResume(params, chatTitles: chatTitles)
        case "job_resume": return try jobResume(params, now: now, chatTitles: chatTitles)
        case "job_delete": return try jobDelete(params, chatTitles: chatTitles)
        case "notification_ack":
            let id = params["notification_id"]?.string
            guard let index = notices.firstIndex(where: { $0["id"]?.string == id }) else {
                throw refusal("Notification not found.")
            }
            notices.remove(at: index)
            return (["acknowledged": 1, "already_acknowledged": 0], [("notification_outbox", [:])])
        case "toolbox_list": return (listing(now: now), [])
        case "toolbox_get": return (try toolDetail(params), [])
        case "toolbox_remove": return try removeTool(params, now: now)
        case "toolbox_undo_remove": return try putBack(params, now: now)
        case "toolbox_decide": return try decide(params, now: now)
        case "screen_sessions":
            return (.array(sessions[params["id"]?.string ?? ""] ?? []), [])
        case "screen_session_revoke": return (try revoke(params), [])
        case "screen_handoff_done": return try handoffDone(params)
        case "model_profiles": return (.array(profiles()), [])
        case "model_select": return try selectModel(params, taskRunning: taskRunning)
        case "model_effort": return try setEffort(params, taskRunning: taskRunning)
        case "setting": return try setting(params, taskRunning: taskRunning, settings: &settings)
        default: return nil
        }
    }

    // MARK: - Schedules

    func dto(_ job: Job) -> JSONValue {
        [
            "id": .string(job.id), "name": .string(job.name), "task": .string(job.task), "schedule": job.schedule,
            "state": .string(job.state), "revision": .int(job.revision), "next_fire": job.nextFire.map(JSONValue.int) ?? .null,
            "error": .null, "last_run_id": .null, "last_run_state": job.lastRunState.map(JSONValue.string) ?? .null,
            "monitor": .bool(job.monitor), "config": configSummary(effort: nil, limits: .null),
        ]
    }

    func configSummary(effort: String?, limits: JSONValue) -> JSONValue {
        [
            "workspace": .null, "workspace_pinned": true,
            "model": ["id": .string(profile), "kind": .string(profile == "chatgpt" ? "chatgpt" : "gguf"), "model": profile == "chatgpt" ? "gpt-5.1" : "Qwen 3.5 9B"],
            "effort": .string(effort ?? efforts[profile] ?? "medium"), "permissions": DemoData.permissions,
            "extensions": "6f1c0e", "mods": 0,
            "limits": limits.object != nil ? limits : ["max_steps": 64, "max_seconds": 900.0],
        ]
    }

    func fingerprint(effort: String?, limits: JSONValue) -> String {
        let limitsText = (try? FrameCodec.jsonText(limits)) ?? "null"
        let seed = "\(profile)|\(effort ?? efforts[profile] ?? "")|\(limitsText)"
        let hex = seed.unicodeScalars.reduce(into: UInt64(14_695_981_039_346_656_037)) { hash, scalar in
            hash = (hash ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return Self.fingerprintPrefix + String(repeating: String(format: "%016llx", hex), count: 4).prefix(60)
    }

    func notificationStatus(chatTitles: [String: String]) -> JSONValue {
        [
            "settings": notifications, "quiet_now": false,
            "outbox": ["pending": 0, "delivered": 4, "suppressed": 0, "failed": 0], "deferred": 0, "last_failure": .null,
            "jobs": .array(jobs.map { job in
                [
                    "job_id": .string(job.id), "chat_id": .string(job.chatID), "label": .string(job.name),
                    "state": .string(job.state == "completed" ? "finished" : job.state), "muted": false,
                ]
            }),
            "actions": ["open"], "lifecycle": .null,
        ]
    }

    func checkChat(_ params: JSONValue, _ chatTitles: [String: String]) throws -> String {
        guard let chat = params["id"]?.string, chatTitles[chat] != nil else { throw refusal("Conversation not found.") }
        return chat
    }

    func jobIndex(_ params: JSONValue, chat: String) throws -> Int {
        guard let id = params["job_id"]?.string, let index = jobs.firstIndex(where: { $0.id == id && $0.chatID == chat })
        else { throw refusal("Job not found in this conversation.") }
        guard params["revision"]?.int == jobs[index].revision else {
            throw refusal("This job changed since you reviewed it. Reload it and try again.")
        }
        return index
    }

    func jobList(_ params: JSONValue, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let chat = try checkChat(params, chatTitles)
        let list = jobs.filter { $0.chatID == chat }.map(dto)
        return (
            [
                "jobs": .array(list), "notifications": [],
                "service": ["running": true, "execution": "while_service_running", "last_error": .null],
            ], []
        )
    }

    func jobGet(_ params: JSONValue, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let chat = try checkChat(params, chatTitles)
        guard let job = jobs.first(where: { $0.id == params["job_id"]?.string && $0.chatID == chat }) else {
            throw refusal("Job not found in this conversation.")
        }
        return (["job": dto(job), "fires": [], "drift": []], [])
    }

    /// Checks a schedule as jobs.py does and gives its next times.
    func nextTimes(_ schedule: JSONValue, now: Date) throws -> [Int] {
        switch schedule["kind"]?.string {
        case "once":
            guard let at = schedule["at"]?.int else { throw refusal("Give a one-time job as whole UTC epoch seconds.") }
            guard Double(at) > now.timeIntervalSince1970, Double(at) < now.timeIntervalSince1970 + 366 * 86_400 else {
                throw refusal("Choose a future UTC time within one year.")
            }
            return [at]
        case "interval":
            guard let seconds = schedule["seconds"]?.int, (60...2_592_000).contains(seconds) else {
                throw refusal("Choose a whole-second interval from 60 seconds to 30 days.")
            }
            return (1...5).map { Int(now.timeIntervalSince1970) + $0 * seconds }
        case "daily":
            guard let time = schedule["time"]?.string, time.count == 5, let hour = Int(time.prefix(2)), let minute = Int(time.suffix(2)),
                (0..<24).contains(hour), (0..<60).contains(minute)
            else { throw refusal("Give a daily time as HH:MM in 24-hour local time.") }
            guard let zone = schedule["timezone"]?.string.flatMap(TimeZone.init(identifier:)) else {
                throw refusal("Use an IANA time zone name such as Europe/London.")
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var times: [Int] = []
            var day = now
            while times.count < 5 {
                if let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), at > now {
                    times.append(Int(at.timeIntervalSince1970))
                }
                day = day.addingTimeInterval(86_400)
            }
            return times
        case nil: throw refusal("A schedule needs a kind: once, interval or daily.")
        default: throw refusal("Use once {at}, interval {seconds} or daily {time, timezone}.")
        }
    }

    func checkLimits(_ limits: JSONValue?) throws -> JSONValue {
        guard let limits else { throw refusal("job_preview accepts effort, id, limits, schedule.") }
        if limits.isNull { return .null }
        guard let object = limits.object, Set(object.keys) == ["max_steps", "max_seconds"] else {
            throw refusal("Run limits accept max_steps and max_seconds.")
        }
        guard let steps = object["max_steps"]?.int, (1...256).contains(steps), let seconds = object["max_seconds"]?.double,
            seconds >= 1, seconds <= 86_400
        else { throw refusal("Choose 1\u{2013}256 steps and 1\u{2013}86400 seconds per run.") }
        return limits
    }

    func jobPreview(_ params: JSONValue, now: Date, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let keys = Set(params.object?.keys ?? [:].keys)
        guard keys.isSuperset(of: ["id", "schedule", "limits"]), keys.isSubset(of: ["id", "schedule", "limits", "effort"]) else {
            throw refusal("job_preview accepts effort, id, limits, schedule.")
        }
        _ = try checkChat(params, chatTitles)
        let limits = try checkLimits(params["limits"])
        let effort = params["effort"]?.string
        let times = try nextTimes(params["schedule"] ?? .null, now: now)
        return (
            [
                "config_fingerprint": .string(fingerprint(effort: effort, limits: limits)),
                "config": configSummary(effort: effort, limits: limits), "schedule": params["schedule"] ?? .null,
                "next_times": .array(times.map(JSONValue.int)),
            ], []
        )
    }

    mutating func jobCreate(_ params: JSONValue, now: Date, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let required: Set<String> = ["id", "name", "task", "schedule", "monitor", "limits", "config_fingerprint"]
        let keys = Set(params.object?.keys ?? [:].keys)
        guard keys.isSuperset(of: required), keys.isSubset(of: required.union(["effort"])) else {
            throw refusal("job_create accepts config_fingerprint, effort, id, limits, monitor, name, schedule, task.")
        }
        let chat = try checkChat(params, chatTitles)
        guard let name = params["name"]?.string, (1...80).contains(name.count), !name.contains("\n") else {
            throw refusal("Use a one-line label of 1 to 80 characters.")
        }
        guard let task = params["task"]?.string else { throw refusal("Give the task as plain text.") }
        guard (1...4000).contains(task.count) else {
            throw refusal("Give a task of up to 4000 characters without control characters.")
        }
        guard let monitor = params["monitor"]?.bool else { throw refusal("monitor must be true or false.") }
        let limits = try checkLimits(params["limits"])
        guard let given = params["config_fingerprint"]?.string, given.count == 64 else {
            throw refusal("Preview the job and pass its config_fingerprint.")
        }
        guard given == fingerprint(effort: params["effort"]?.string, limits: limits) else {
            throw refusal(
                "The reviewed configuration no longer matches the current settings. Preview the job again and review the result.")
        }
        let times = try nextTimes(params["schedule"] ?? .null, now: now)
        guard jobs.count < 64 else { throw refusal("Keep at most 64 scheduled jobs. Delete one first.") }
        let job = Job(
            id: String(format: "job-%04d", jobs.count + 1), chatID: chat, name: name, task: task,
            schedule: params["schedule"] ?? .null, state: "active", revision: 1, nextFire: times.first, monitor: monitor,
            lastRunState: nil)
        jobs.append(job)
        return (dto(job), [jobEvent(job)])
    }

    mutating func jobPause(_ params: JSONValue, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let index = try jobIndex(params, chat: try checkChat(params, chatTitles))
        guard ["active", "needs_review"].contains(jobs[index].state) else {
            throw refusal("Only an active job or one awaiting review can be paused.")
        }
        jobs[index].state = "paused"
        jobs[index].nextFire = nil
        jobs[index].revision += 1
        return (dto(jobs[index]), [jobEvent(jobs[index])])
    }

    func jobPreviewResume(_ params: JSONValue, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let index = try jobIndex(params, chat: try checkChat(params, chatTitles))
        guard ["paused", "needs_review"].contains(jobs[index].state) else {
            throw refusal("Only a paused job or one awaiting review can be resumed.")
        }
        return (
            ["config_fingerprint": .string(fingerprint(effort: nil, limits: .null)), "config": configSummary(effort: nil, limits: .null)],
            []
        )
    }

    mutating func jobResume(_ params: JSONValue, now: Date, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let index = try jobIndex(params, chat: try checkChat(params, chatTitles))
        guard ["paused", "needs_review"].contains(jobs[index].state) else {
            throw refusal("Only a paused job or one awaiting review can be resumed.")
        }
        guard params["config_fingerprint"]?.string == fingerprint(effort: nil, limits: .null) else {
            throw refusal(
                "The reviewed configuration no longer matches the current settings. Preview the job again and review the result.")
        }
        jobs[index].state = "active"
        jobs[index].revision += 2  // updated, then resumed
        jobs[index].nextFire = try nextTimes(jobs[index].schedule, now: now).first
        return (dto(jobs[index]), [jobEvent(jobs[index])])
    }

    mutating func jobDelete(_ params: JSONValue, chatTitles: [String: String]) throws -> (JSONValue, [Event]) {
        let chat = try checkChat(params, chatTitles)
        let index = try jobIndex(params, chat: chat)
        let job = jobs.remove(at: index)
        return (
            ["job_id": .string(job.id), "deleted": true],
            [("job", ["chat_id": .string(chat), "job_id": .string(job.id), "state": "deleted"])]
        )
    }

    func jobEvent(_ job: Job) -> Event {
        ("job", ["chat_id": .string(job.chatID), "job_id": .string(job.id), "state": .string(job.state), "revision": .int(job.revision)])
    }

    // MARK: - Toolbox

    func listing(now: Date) -> JSONValue {
        [
            "tools": .array(tools.map { tool in
                [
                    "name": .string(tool.name), "purpose": .string(tool.purpose), "kept_by": .string(tool.keptBy),
                    "kept_at": .double(tool.keptAt), "uses": .int(tool.uses), "last_used": .null, "state": "ok",
                    "digest": "a1b2c3d4e5f60718",
                ]
            }),
            "pending": .array(pending),
            "removed": .array(removed.compactMap { entry in
                let left = Int(600 - now.timeIntervalSince(entry.at))
                return left > 0 ? ["name": .string(entry.tool.name), "purpose": .string(entry.tool.purpose), "seconds_left": .int(left)] : nil
            }),
        ]
    }

    func toolDetail(_ params: JSONValue) throws -> JSONValue {
        guard let tool = tools.first(where: { $0.name == params["name"]?.string }) else {
            throw refusal("No kept tool has that name.")
        }
        return [
            "name": .string(tool.name), "purpose": .string(tool.purpose), "code": .string(tool.code),
            "tests": [["args": ["x": 1], "expect": 1], ["args": ["x": 2], "expect": 2], ["args": ["x": 3], "expect": 3]],
            "inputs": ["type": "object", "properties": [:], "required": []],
            "validation": ["tests": 3, "cases_run": 50, "seconds": 0.8, "findings": []], "blind": ["run": 5, "passed": 5],
            "provenance": ["run_id": "r-weather", "reason": "kept", "made_at": .double(tool.keptAt), "model": "gpt-5.1"],
            "verified": true,
        ]
    }

    mutating func removeTool(_ params: JSONValue, now: Date) throws -> (JSONValue, [Event]) {
        guard let index = tools.firstIndex(where: { $0.name == params["name"]?.string }) else {
            throw refusal("No kept tool has that name.")
        }
        removed.append((tools.remove(at: index), now))
        if removed.count > 5 { removed.removeFirst() }
        return (listing(now: now), [])
    }

    mutating func putBack(_ params: JSONValue, now: Date) throws -> (JSONValue, [Event]) {
        guard let index = removed.firstIndex(where: { $0.tool.name == params["name"]?.string && now.timeIntervalSince($0.at) < 600 })
        else { throw refusal("That tool can no longer be put back (after ten minutes it is gone for good).") }
        if tools.contains(where: { $0.name == removed[index].tool.name }) {
            throw refusal("A tool with that name is in the Toolbox again.")
        }
        tools.append(removed.remove(at: index).tool)
        return (listing(now: now), [])
    }

    mutating func decide(_ params: JSONValue, now: Date) throws -> (JSONValue, [Event]) {
        guard let index = pending.firstIndex(where: { $0["id"]?.string == params["pending_id"]?.string }) else {
            throw refusal("That request is no longer waiting.")
        }
        let asked = pending.remove(at: index)
        if params["keep"]?.bool == true {  // only JSON true keeps
            tools.removeAll { $0.name == asked["name"]?.string }
            tools.append(
                Tool(
                    name: asked["name"]?.string ?? "tool", purpose: asked["purpose"]?.string ?? "", keptBy: "person",
                    keptAt: now.timeIntervalSince1970, uses: 0, code: "def split_bill(total, people, tip=0.15):\n    return round(total * (1 + tip) / people, 2)\n"))
        }
        return (listing(now: now), [])
    }

    // MARK: - Screen sessions

    mutating func revoke(_ params: JSONValue) throws -> JSONValue {
        guard let id = params["session_id"]?.string, !id.isEmpty else {
            throw RemoteCallError.refused(PersonFacingError(message: "The screen request is malformed.", code: "invalid"))
        }
        for (chat, list) in sessions {
            if let index = list.firstIndex(where: { $0["session_id"]?.string == id }), ["active", "handoff", "interrupted"].contains(list[index]["state"]?.string ?? "") {
                var session = list[index].object ?? [:]
                session["state"] = "revoked"
                sessions[chat]?[index] = .object(session)
                return 1
            }
        }
        return 0
    }

    mutating func handoffDone(_ params: JSONValue) throws -> (JSONValue, [Event]) {
        let id = params["session_id"]?.string
        for (chat, list) in sessions {
            guard let index = list.firstIndex(where: { $0["session_id"]?.string == id }) else { continue }
            guard list[index]["state"]?.string != "revoked" else {
                throw RemoteCallError.refused(PersonFacingError(message: "The person revoked this screen session.", code: "session_revoked"))
            }
            guard list[index]["state"]?.string != "active" else {
                throw RemoteCallError.refused(
                    PersonFacingError(message: "The screen request is malformed. The session is already active.", code: "invalid"))
            }
            var session = list[index].object ?? [:]
            session["state"] = "active"
            session["reason"] = .null
            sessions[chat]?[index] = .object(session)
            return (["session_id": .string(id ?? ""), "state": "active", "fresh_observation_required": true], [])
        }
        throw RemoteCallError.refused(
            PersonFacingError(message: "There is no such screen session. Ask the person to grant a window or tab in Pebble.", code: "unknown_session"))
    }

    // MARK: - Models

    func profiles() -> [JSONValue] {
        [
            [
                "id": "chatgpt", "name": "ChatGPT", "kind": "chatgpt", "model": "gpt-5.1", "display_name": "GPT-5.1",
                "context": 272_000, "tools": true, "local": false, "connection_id": "chatgpt", "provider_name": "ChatGPT",
                "efforts": ["default", "low", "medium", "high"], "default_effort": "medium",
                "effort": .string(efforts["chatgpt"] ?? "medium"), "effort_parameter": "reasoning",
            ],
            [
                "id": "default-local", "kind": "gguf", "name": "Qwen 3.5 9B", "path": "/Users/you/Models/qwen3.5-9b.gguf",
                "context": 4096, "tools": true, "connection_id": "local", "provider_name": "On this device",
                "efforts": ["quick", "think"], "default_effort": "think", "effort": .string(efforts["default-local"] ?? "think"),
                "effort_parameter": "local_thinking",
            ],
        ]
    }

    /// state().model / the `model` event for the profile in use.
    func modelStatus() -> JSONValue {
        if profile == "default-local" {
            return [
                "state": .string(localModelState), "configured": true, "name": "qwen3.5-9b",
                "path": "/Users/you/Models/qwen3.5-9b.gguf",
                "context": 4096, "kind": "gguf", "profile_id": "default-local", "efforts": ["quick", "think"],
                "default_effort": "think", "effort": .string(efforts["default-local"] ?? "think"),
            ]
        }
        return [
            "state": "ready", "configured": true, "name": "gpt-5.1", "path": "", "context": 272_000, "kind": "chatgpt",
            "profile_id": "chatgpt", "local": false, "provider": "ChatGPT", "budget": 272_000, "protocol": "responses",
            "efforts": ["default", "low", "medium", "high"], "default_effort": "medium",
            "effort": .string(efforts["chatgpt"] ?? "medium"),
        ]
    }

    mutating func selectModel(_ params: JSONValue, taskRunning: Bool) throws -> (JSONValue, [Event]) {
        if taskRunning { throw refusal("Stop the current task before changing models.") }
        guard let id = params["profile_id"]?.string, ["chatgpt", "default-local"].contains(id) else {
            throw refusal("Model profile not found.")
        }
        profile = id
        return (modelStatus(), [("model", modelStatus())])
    }

    mutating func setEffort(_ params: JSONValue, taskRunning: Bool) throws -> (JSONValue, [Event]) {
        if taskRunning { throw refusal("Stop the current task before changing effort.") }
        let offered = (modelStatus()["efforts"]?.array ?? []).compactMap(\.string)
        guard let effort = params["effort"]?.string, offered.contains(effort) else {
            throw refusal("This model does not support that effort level. Choose one of its available settings.")
        }
        efforts[profile] = effort
        return (modelStatus(), [("model", modelStatus())])
    }

    // MARK: - Settings (app.py setting(): each key takes its whole value)

    mutating func setting(_ params: JSONValue, taskRunning: Bool, settings: inout [String: JSONValue]) throws -> (JSONValue, [Event]) {
        let key = params["key"]?.string ?? ""
        let value = params["value"] ?? .null
        func bools(_ value: JSONValue, _ names: Set<String>) -> Bool {
            guard let object = value.object else { return false }
            return Set(object.keys) == names && object.values.allSatisfy { $0.bool != nil }
        }
        var events: [Event] = [("settings", [:])]
        switch key {
        case "permissions":
            if taskRunning { throw refusal("Stop the task before changing permissions.") }
            guard let object = value.object, Set(object.keys) == ["mode", "tools"],
                let mode = object["mode"]?.string, ["ask", "auto", "full"].contains(mode)
            else { throw refusal("Choose Ask, Auto, or Full access.") }
            let required: Set<String> = ["files", "edits", "tests", "apps", "web", "terminal", "plugins", "views"]
            guard let tools = object["tools"]?.object, required.isSubset(of: Set(tools.keys)),
                Set(tools.keys).isSubset(of: required.union(["screen", "capture"])), tools.values.allSatisfy({ $0.bool != nil })
            else { throw refusal("Invalid tool permissions.") }
            settings[key] = value
        case "fast_replies":
            guard let raw = value.string, FastReplies(rawValue: raw) != nil else {
                throw refusal("fast_replies is \"off\", \"follow_ups\", \"long_tasks\" or \"always\".")
            }
            settings[key] = value
        case "git_decisions":
            guard bools(value, ["force_push", "delete_remote_branch", "repository_identity", "clean"]) else {
                throw refusal(
                    "git_decisions needs true or false for each of: force_push, delete_remote_branch, repository_identity, clean.")
            }
            settings[key] = value
        case "memory_layers":
            guard bools(value, Set(RemoteStore.memoryLayerNames)) else {
                throw refusal("Supply one boolean for each of the six memory layers.")
            }
            settings[key] = value
        case "theme":
            guard let theme = value.string, ["system", "light", "dark"].contains(theme) else { throw refusal("Setting is not supported.") }
            settings[key] = value
        case "reduced_motion", "memory_enabled", "stealth":
            guard value.bool != nil else { throw refusal("Setting is not supported.") }
            settings[key] = value
        case "companion":
            guard let object = value.object, Set(object.keys) == ["pointer", "reactions", "status_words", "ui_guidance"] else {
                throw refusal("Supply exactly pointer, reactions, status_words and ui_guidance for the companion.")
            }
            guard object["pointer"]?.bool != nil, object["reactions"]?.bool != nil, object["ui_guidance"]?.bool != nil else {
                throw refusal("Companion pointer, reactions and UI guidance are each on or off.")
            }
            guard let words = object["status_words"]?.string, ["rotate", "fixed", "off"].contains(words) else {
                throw refusal("Companion status words are rotate, fixed or off.")
            }
            settings[key] = value
        case "notifications":
            guard let object = value.object, Set(object.keys).isSuperset(of: ["enabled", "kinds", "preview", "quiet_hours"]),
                Set(object.keys).isSubset(of: ["enabled", "kinds", "preview", "quiet_hours", "replies"])
            else { throw refusal("Notification settings need exactly enabled, kinds, preview and quiet_hours (and replies).") }
            guard object["enabled"]?.bool != nil else { throw refusal("enabled must be true or false.") }
            guard bools(object["kinds"] ?? .null, ["completed", "failed", "action_needed", "monitor_changed"]) else {
                throw refusal("Give one true or false for each kind: completed, failed, action_needed, monitor_changed.")
            }
            guard let preview = object["preview"]?.string, ["none", "title", "body"].contains(preview) else {
                throw refusal("Choose a content preview of none, title or body.")
            }
            if let quiet = object["quiet_hours"], !quiet.isNull {
                guard let hours = quiet.object, Set(hours.keys) == ["start", "end", "timezone"] else {
                    throw refusal("Quiet hours need exactly start, end and timezone, or null.")
                }
                guard hours["start"]?.string != hours["end"]?.string else { throw refusal("Quiet hours need different start and end times.") }
            }
            if let replies = object["replies"], replies.bool == nil { throw refusal("replies must be true or false.") }
            var saved = object
            if saved["replies"] == nil { saved["replies"] = true }
            notifications = .object(saved)
            events.append(("notification_outbox", [:]))
        default:
            throw refusal("Setting is not supported.")
        }
        return (true, events)
    }

    func refusal(_ message: String) -> RemoteCallError {
        .refused(PersonFacingError(message: message))
    }
}

import Foundation
import PebbleProtocol

// Schedules, Pebble's Toolbox and screen sessions, as Pebble's own windows show them (read-only Pebble checkout:
// backend/pebble/job_api.py, jobs.py, workshop.py, screen_session.py; src/components/CompanionWorkflows.vue,
// AdvancedSettings.vue, ScreenSessions.vue). Value types; RemoteStore builds them from Pebble's answers.

// MARK: - Schedules

/// When a scheduled job runs (Pebble's tagged schedule: no cron).
public enum ScheduleSpec: Sendable, Hashable {
    /// Once, at a time within the next year.
    case once(at: Date)
    /// Every so many seconds, from 60 seconds to 30 days.
    case interval(seconds: Int)
    /// Every day at "HH:MM" (24-hour) in an IANA time zone.
    case daily(time: String, timezone: String)

    /// What a late time does: run once when Pebble can (latest), or skip it after `graceSeconds` (60 to 86,400).
    public enum CatchUp: Sendable, Hashable {
        case latest
        case skipIfLate(graceSeconds: Int?)
    }

    public init?(json: JSONValue) {
        switch json["kind"]?.string {
        case "once": guard let at = json["at"]?.double else { return nil }; self = .once(at: Date(timeIntervalSince1970: at))
        case "interval": guard let seconds = json["seconds"]?.int else { return nil }; self = .interval(seconds: seconds)
        case "daily":
            guard let time = json["time"]?.string, let zone = json["timezone"]?.string else { return nil }
            self = .daily(time: time, timezone: zone)
        default: return nil
        }
    }

    /// Pebble's wire form, with the catch-up choice (latest is sent as nothing).
    public func json(catchUp: CatchUp = .latest) -> JSONValue {
        var object: [String: JSONValue]
        switch self {
        case .once(let at): object = ["kind": "once", "at": .int(Int(at.timeIntervalSince1970.rounded()))]
        case .interval(let seconds): object = ["kind": "interval", "seconds": .int(seconds)]
        case .daily(let time, let zone): object = ["kind": "daily", "time": .string(time), "timezone": .string(zone)]
        }
        if case .skipIfLate(let grace) = catchUp {
            object["catch_up"] = "skip_if_late"
            if let grace { object["grace_seconds"] = .int(grace) }
        }
        return .object(object)
    }
}

/// A scheduled job ("Morning summary": its task runs in its conversation on its schedule).
public struct ScheduleItem: Sendable, Hashable, Identifiable {
    public var id: String
    /// The conversation it runs in.
    public var chatID: ChatID
    public var chatTitle: String
    /// Its one-line label.
    public var name: String
    /// What Pebble does each time.
    public var task: String
    public var schedule: ScheduleSpec?
    public var catchUp: ScheduleSpec.CatchUp
    /// active, paused, needs_review or completed.
    public var state: String
    /// Pebble's revision: every change must name the one it saw.
    public var revision: Int
    public var nextRun: Date?
    /// Why it needs a look (Pebble's words), when it does.
    public var problem: String?
    public var lastRunState: RunState?
    /// It only reports a change in the result.
    public var monitor: Bool

    public var isPaused: Bool { state == "paused" }
    public var needsReview: Bool { state == "needs_review" }

    public init(
        id: String, chatID: ChatID, chatTitle: String, name: String, task: String = "", schedule: ScheduleSpec? = nil,
        catchUp: ScheduleSpec.CatchUp = .latest, state: String, revision: Int, nextRun: Date? = nil,
        problem: String? = nil, lastRunState: RunState? = nil, monitor: Bool = false
    ) {
        self.id = id
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.name = name
        self.task = task
        self.schedule = schedule
        self.catchUp = catchUp
        self.state = state
        self.revision = revision
        self.nextRun = nextRun
        self.problem = problem
        self.lastRunState = lastRunState
        self.monitor = monitor
    }

    /// From job_list / job_get / job_create's job (job_api `_dto`).
    public init?(json: JSONValue, chatID: ChatID, chatTitle: String) {
        guard let id = json["id"]?.string, !id.isEmpty else { return nil }
        let schedule = json["schedule"] ?? .null
        let catchUp: ScheduleSpec.CatchUp =
            schedule["catch_up"]?.string == "skip_if_late" ? .skipIfLate(graceSeconds: schedule["grace_seconds"]?.int) : .latest
        self.init(
            id: id, chatID: chatID, chatTitle: chatTitle, name: json["name"]?.string ?? "", task: json["task"]?.string ?? "",
            schedule: ScheduleSpec(json: schedule), catchUp: catchUp, state: json["state"]?.string ?? "active",
            revision: json["revision"]?.int ?? 0, nextRun: json["next_fire"]?.double.map { Date(timeIntervalSince1970: $0) },
            problem: json["error"]?.string, lastRunState: json["last_run_state"]?.string.map(RunState.init(rawValue:)),
            monitor: json["monitor"]?.bool ?? false)
    }
}

/// What a schedule will run with, for the person to review before Face ID (job_preview, job_preview_resume): the
/// fingerprint Pebble checks on create and resume, and the configuration in Pebble's summary.
public struct ScheduleReview: Sendable, Hashable {
    public var fingerprint: String
    /// Pebble's summary: workspace, model, effort, permissions, limits.
    public var config: JSONValue
    /// The next times it would run (job_preview only).
    public var nextTimes: [Date]
    /// The limits and effort the preview was made with; creating must send the same.
    public var limits: JSONValue
    public var effort: String?

    public init(fingerprint: String, config: JSONValue, nextTimes: [Date] = [], limits: JSONValue = .null, effort: String? = nil) {
        self.fingerprint = fingerprint
        self.config = config
        self.nextTimes = nextTimes
        self.limits = limits
        self.effort = effort
    }

    public var workspace: String? { config["workspace"]?.string }
    public var modelName: String? { config["model"]?["model"]?.string }
    public var mode: PermissionMode? { config["permissions"]?["mode"]?.string.flatMap(PermissionMode.init(rawValue:)) }
}

/// A notice from a scheduled job that the person has not acknowledged (state().job_notifications).
public struct JobNotice: Sendable, Hashable, Identifiable {
    public var id: String
    public var chatID: ChatID
    /// Pebble's words: "Scheduled job “Morning summary” completed".
    public var title: String
    public var created: Date?

    public init(id: String, chatID: ChatID, title: String, created: Date?) {
        self.id = id
        self.chatID = chatID
        self.title = title
        self.created = created
    }
}

// MARK: - Pebble's Toolbox

/// A tool Pebble made and kept (Pebble's Workshop).
public struct ToolboxEntry: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    /// What it is for, in Pebble's words.
    public var purpose: String
    /// Pebble kept it on its own (validated, used, untainted), or the person did.
    public var keptByPebble: Bool
    public var keptAt: Date?
    public var uses: Int
    public var lastUsed: Date?
    public var needsAttention: Bool

    public init(
        name: String, purpose: String, keptByPebble: Bool, keptAt: Date? = nil, uses: Int = 0, lastUsed: Date? = nil,
        needsAttention: Bool = false
    ) {
        self.name = name
        self.purpose = purpose
        self.keptByPebble = keptByPebble
        self.keptAt = keptAt
        self.uses = uses
        self.lastUsed = lastUsed
        self.needsAttention = needsAttention
    }

    init?(json: JSONValue) {
        guard let name = json["name"]?.string, !name.isEmpty else { return nil }
        self.init(
            name: name, purpose: json["purpose"]?.string ?? "", keptByPebble: json["kept_by"]?.string == "pebble",
            keptAt: unixDate(json["kept_at"]), uses: json["uses"]?.int ?? 0, lastUsed: unixDate(json["last_used"]),
            needsAttention: json["state"]?.string == "needs_attention")
    }
}

/// A tool Pebble asks the person to keep or discard, with Pebble's reasons ("it has not been used successfully in
/// this task yet").
public struct ToolboxDecision: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var purpose: String
    public var why: [String]
    public var chatID: ChatID?

    init?(json: JSONValue) {
        guard let id = json["id"]?.string ?? json["pending_id"]?.string, let name = json["name"]?.string else { return nil }
        self.id = id
        self.name = name
        purpose = json["purpose"]?.string ?? ""
        why = (json["why"]?.array ?? []).compactMap(\.string)
        chatID = json["chat_id"]?.string
    }
}

/// A tool removed in the last ten minutes, which can still be put back.
public struct RemovedTool: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var purpose: String
    public var secondsLeft: Int

    init?(json: JSONValue) {
        guard let name = json["name"]?.string else { return nil }
        self.name = name
        purpose = json["purpose"]?.string ?? ""
        secondsLeft = json["seconds_left"]?.int ?? 0
    }
}

/// One kept tool in detail (toolbox_get): its code and how it was checked.
public struct ToolDetail: Sendable, Hashable {
    public var name: String
    public var purpose: String
    public var code: String
    public var tests: Int
    public var verified: Bool

    init?(json: JSONValue) {
        guard let name = json["name"]?.string else { return nil }
        self.name = name
        purpose = json["purpose"]?.string ?? ""
        code = json["code"]?.string ?? ""
        tests = json["tests"]?.array?.count ?? json["validation"]?["tests"]?.int ?? 0
        verified = json["verified"]?.bool ?? false
    }
}

// MARK: - Screen and browser sessions

/// A window or browser tab Pebble may use for a while (screen_sessions): "Can look around, fill in, press buttons".
public struct ScreenSession: Sendable, Hashable, Identifiable {
    public var id: String
    public var chatID: ChatID
    public var runID: RunID?
    /// "app" (a Mac app's window) or "browser" (a tab).
    public var kind: String
    /// The app's bundle id ("com.apple.calculator"), for an app window.
    public var bundleID: String?
    /// For a tab: "pebble" (Pebble's own browser) or "chrome" (the person's Chrome).
    public var profile: String?
    /// The sites it may act on.
    public var origins: [String]
    /// What Pebble may do there: focus, scroll, expand, collapse, select, toggle, type, press, enter.
    public var actions: [String]
    /// active, handoff, interrupted, revoked, expired, restarted.
    public var state: String
    public var expires: Date?
    /// Granted, waiting for the conversation's next message.
    public var pending: Bool
    /// Why it was handed back to the person (Pebble's reason codes, such as "login_form").
    public var reasons: [String]

    /// The app's short name from its bundle id ("calculator"), as Pebble's window shows it.
    public var appName: String? { bundleID?.split(separator: ".").last.map(String.init) }

    /// Still usable at `date`: a live state and not past its time (Pebble ends sessions lazily).
    public func isLive(at date: Date) -> Bool {
        ["active", "handoff", "interrupted"].contains(state) && (expires.map { $0 > date } ?? true)
    }

    public init(
        id: String, chatID: ChatID, runID: RunID? = nil, kind: String = "app", bundleID: String? = nil,
        profile: String? = nil, origins: [String] = [], actions: [String] = [], state: String = "active",
        expires: Date? = nil, pending: Bool = false, reasons: [String] = []
    ) {
        self.id = id
        self.chatID = chatID
        self.runID = runID
        self.kind = kind
        self.bundleID = bundleID
        self.profile = profile
        self.origins = origins
        self.actions = actions
        self.state = state
        self.expires = expires
        self.pending = pending
        self.reasons = reasons
    }

    init?(json: JSONValue, chatID: ChatID) {
        guard let id = json["session_id"]?.string, !id.isEmpty else { return nil }
        self.id = id
        self.chatID = chatID
        runID = json["run_id"]?.string
        let target = json["target"] ?? .null
        kind = json["kind"]?.string ?? target["kind"]?.string ?? "app"
        bundleID = target["bundle_id"]?.string
        profile = target["profile"]?.string
        origins = (target["origins"]?.array ?? []).compactMap(\.string)
        actions = (json["actions"]?.array ?? []).compactMap(\.string)
        state = json["state"]?.string ?? "active"
        expires = unixDate(json["expires"])
        pending = json["pending"]?.bool ?? false
        reasons = (json["reason"]?["reasons"]?.array ?? []).compactMap(\.string)
    }
}

// MARK: - Recently deleted

/// A conversation in Recently deleted (storage_summary): Pebble deletes it for good after 30 days.
public struct TrashedChat: Sendable, Hashable, Identifiable {
    public var id: ChatID
    public var title: String
    public var deleted: Date?
    public var deleteAfter: Date?

    public init(id: ChatID, title: String, deleted: Date? = nil, deleteAfter: Date? = nil) {
        self.id = id
        self.title = title
        self.deleted = deleted
        self.deleteAfter = deleteAfter
    }

    init?(json: JSONValue) {
        guard let id = json["chat_id"]?.string, !id.isEmpty else { return nil }
        self.init(
            id: id, title: json["title"]?.string ?? "", deleted: unixDate(json["deleted"]),
            deleteAfter: unixDate(json["delete_after"]))
    }
}

// MARK: - Attachments

/// A photo or file waiting to go with the conversation's next message (attach_bytes' chip).
public struct AttachmentRef: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// image, document, spreadsheet, archive, text or file.
    public var kind: String
    /// A small JPEG preview of an image.
    public var preview: Data?
    public var bytes: Int?

    public init(id: String, name: String, kind: String, preview: Data? = nil, bytes: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.preview = preview
        self.bytes = bytes
    }

    init?(json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty else { return nil }
        var preview: Data?
        if let url = json["preview"]?.string, let comma = url.firstIndex(of: ","), url.hasPrefix("data:") {
            preview = Data(base64Encoded: String(url[url.index(after: comma)...]))
        }
        self.init(
            id: id, name: json["name"]?.string ?? "", kind: json["kind"]?.string ?? "file", preview: preview,
            bytes: json["bytes"]?.int)
    }
}

// MARK: - Lists the store reads on request

/// The Control tab's lists: read when a screen asks (`loadControlLists()`, or one at a time), and again when an
/// event says they changed.
public enum ControlList: String, Sendable, Hashable, CaseIterable {
    case models, devices, schedules, toolbox, screenSessions, trash, notifications
}

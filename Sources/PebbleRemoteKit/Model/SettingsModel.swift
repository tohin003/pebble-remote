import Foundation
import PebbleProtocol

// Lane S (2026-10-31): the Settings controls that were "On your Mac" rows, read as Pebble's own Settings read them
// (read-only Pebble checkout: AdvancedSettings.vue, StorageSettings.vue, TelemetrySettings.vue,
// NotificationSettings.vue; app.py and the modules behind it). Every reader is tolerant: unknown fields are ignored, a
// record without what identifies it yields nil, and a value of the wrong type reads as missing.

// MARK: - Settings › Memory: learning candidates and memories saved by hand (SY-12, SY-16)

/// A proposal Pebble's learning holds (`memory_candidates`: rows of its candidates table, newest first). Pebble's
/// Memory settings show three of its states: waiting for evidence, disagreeing with a saved memory, and not saved.
public struct MemoryCandidate: Sendable, Hashable, Identifiable {
    public var id: String
    /// The layer it would join.
    public var kind: String
    /// "pending", "conflict" or "unsupported" for the ones Pebble's settings show (`shownStates`).
    public var status: String
    /// Why it waits, as Pebble's code; the screen says it in words. Nil when Pebble gives none.
    public var reason: String?
    /// The proposed words; empty for a test recipe (the screen says so in Pebble's words).
    public var content: String
    /// "global" (personal), "chat:<id>" (a conversation) or a project's folder.
    public var scope: String
    public var updated: Date?

    /// The states Pebble's Memory settings list (AdvancedSettings.vue: pending, conflict, unsupported).
    public static let shownStates: Set<String> = ["pending", "conflict", "unsupported"]

    public init(
        id: String, kind: String, status: String, reason: String? = nil, content: String = "", scope: String = "global",
        updated: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.reason = reason
        self.content = content
        self.scope = scope
        self.updated = updated
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty, let kind = json["kind"]?.string, !kind.isEmpty,
            let status = json["status"]?.string
        else { return nil }
        self.init(
            id: id, kind: kind, status: status, reason: json["reason"]?.string, content: json["content"]?.string ?? "",
            scope: json["scope"]?.string ?? "", updated: unixDate(json["updated"]))
    }

    /// It disagrees with a saved memory: the person chooses "Use this value" or "Keep current".
    public var disagrees: Bool { status == "conflict" }
}

/// Where a memory saved by hand is recalled (Pebble's "Recall scope").
public enum MemoryRecall: Sendable, Hashable {
    /// "Personal · all conversations".
    case personal
    /// A project's conversations: Pebble keeps the memory with the project's folder (app.py `memory_save`, V1-021).
    case project(ProjectRef)
}

/// The layers a memory can be added to by hand: Pebble records task context and past experiences itself (app.py
/// `memory_save` refuses them).
public enum MemoryLayers {
    public static let recordedByPebble: Set<String> = ["working", "episodic"]
    /// The layer that needs an expiry ("Time-sensitive information").
    public static let timeSensitive = "temporal"
    /// The most a memory may hold, in characters (memory.py `put`; the Mac's field stops there too).
    public static let longest = 4000

    public static func takesMemoriesByHand(_ layer: String) -> Bool { !recordedByPebble.contains(layer) }
}

// MARK: - Settings › Skills & connectors (SK-04, SK-05, SK-06, SK-09)

/// A skill, connector or hook in Pebble's Skills & connectors (`extensions`, oldest first). Its words and configuration
/// are Pebble's data, shown literally; a connector's credentials are never in them.
public struct ExtensionItem: Sendable, Hashable, Identifiable {
    public var id: String
    /// "skill", "plugin" (a connector) or "hook"; another kind from a newer Pebble shows as Pebble names it.
    public var kind: String
    public var name: String
    public var enabled: Bool
    /// What it can do (extensions.py): a connector's tools, "task guidance" for a skill, a hook's rule.
    public var capabilities: [String]
    /// What the Mac's Review shows first: a skill's instructions, a hook's rule, a connector's manifest.
    public var content: String
    public var connector: Connector?
    public var skill: Skill?

    /// A connector's reviewed destination, as the Mac's Review lists it.
    public struct Connector: Sendable, Hashable {
        /// "http" unless Pebble says otherwise ("stdio": a program on the Mac).
        public var transport: String
        /// The MCP protocol era it was added with ("legacy" unless Pebble says).
        public var protocolEra: String
        /// The service's address, or the local program's command.
        public var address: String
        /// The reviewed version of its tools (`catalogue_digest`), once it was enabled.
        public var reviewedVersion: String?
        public var protocolVersion: String?
        /// Its launch files and its tools' input schemas, as indented text (the Mac shows both as JSON).
        public var launchFiles: String?
        public var schemas: String?
        /// From a connector package: its checksum.
        public var packageChecksum: String?
        /// Its configuration names an access grant (`auth_binding`). Whether that grant still works is on the Mac:
        /// `connector_metadata`, which says so, is a sign-in method the phone can't call (contract 3.7).
        public var holdsGrant: Bool
    }

    /// An imported skill's pinned snapshot and its files.
    public struct Skill: Sendable, Hashable {
        /// The snapshot's checksum (`bundle_digest`); `skill_inspect` reads only this snapshot.
        public var snapshot: String
        /// The main instructions' path (the Review shows them as `content`).
        public var main: String?
        public var files: [SkillFile]
    }

    public struct SkillFile: Sendable, Hashable, Identifiable {
        public var path: String
        public var bytes: Int?
        public var sha256: String
        /// The Mac offers "View text" for a reference file that is text: not the main instructions, and one of
        /// md, txt, json, yaml, yml, py, js, ts or svg (AdvancedSettings.vue).
        public var readable: Bool
        public var id: String { path }
    }

    public init(
        id: String, kind: String, name: String, enabled: Bool = false, capabilities: [String] = [],
        content: String = "", connector: Connector? = nil, skill: Skill? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.enabled = enabled
        self.capabilities = capabilities
        self.content = content
        self.connector = connector
        self.skill = skill
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty, let kind = json["kind"]?.string else { return nil }
        let config = json["config"]?.object ?? [:]
        self.init(
            id: id, kind: kind, name: json["name"]?.string ?? "", enabled: json["enabled"]?.bool ?? false,
            capabilities: (json["capabilities"]?.array ?? []).compactMap(\.string),
            content: json["content"]?.string ?? "",
            connector: kind == "plugin" ? Connector(config: config) : nil,
            skill: kind == "skill" ? Skill(config: config) : nil)
    }

    /// A reference file the Mac reads as text (AdvancedSettings.vue's pattern).
    static func readsAsText(_ path: String) -> Bool {
        let pattern = #"\.(md|txt|json|yaml|yml|py|js|ts|svg)$"#
        return path.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension ExtensionItem.Connector {
    init(config: [String: JSONValue]) {
        func words(_ key: String) -> String? { config[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        func shown(_ key: String) -> String? {
            guard let value = config[key], value != .null else { return nil }
            if let list = value.array, list.isEmpty { return nil }
            if let object = value.object, object.isEmpty { return nil }
            return value.indentedText
        }
        self.init(
            transport: words("transport") ?? "http", protocolEra: words("protocol_era") ?? "legacy",
            address: words("url") ?? words("command") ?? "", reviewedVersion: words("catalogue_digest"),
            protocolVersion: words("protocol"), launchFiles: shown("launch_files"), schemas: shown("schemas"),
            packageChecksum: words("package_digest"), holdsGrant: config["auth_binding"]?.object != nil)
    }
}

extension ExtensionItem.Skill {
    /// Nil for a skill without a pinned snapshot (the Mac shows no files then).
    init?(config: [String: JSONValue]) {
        guard let snapshot = config["bundle_digest"]?.string, !snapshot.isEmpty else { return nil }
        let main = config["main"]?.string
        let files = (config["files"]?.array ?? []).compactMap { file -> ExtensionItem.SkillFile? in
            guard let path = file["path"]?.string, !path.isEmpty else { return nil }
            return ExtensionItem.SkillFile(
                path: path, bytes: file["bytes"]?.int, sha256: file["sha256"]?.string ?? "",
                readable: path != main && ExtensionItem.readsAsText(path))
        }
        self.init(snapshot: snapshot, main: main, files: files)
    }
}

/// One page of a skill's reference file (`skill_inspect`): Pebble pages a file 3,000 characters at a time.
public struct SkillTextPage: Sendable, Hashable {
    public var path: String
    public var text: String
    /// Where the next page starts; nil at the end.
    public var nextOffset: Int?

    public init(path: String, text: String, nextOffset: Int? = nil) {
        self.path = path
        self.text = text
        self.nextOffset = nextOffset
    }

    public init?(json: JSONValue) {
        guard let path = json["path"]?.string, let text = json["untrusted_source"]?.string else { return nil }
        self.init(path: path, text: text, nextOffset: json["next_offset"]?.int)
    }
}

extension JSONValue {
    /// Indented JSON text with sorted keys, as Pebble's window shows a configuration (`JSON.stringify(value, null,
    /// 2)`).
    var indentedText: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

// MARK: - Settings › Data & storage (SD-11, SD-12, SD-14, SD-15)

/// What Pebble's Data & storage page says about the person's files and Recently deleted (`storage_summary`, and
/// `storage_refresh` after a copy pass). The phone reads the parts it shows; the folders and sizes stay on the Mac.
public struct StorageOverview: Sendable, Hashable {
    /// "Recent changes from your files", newest first (Pebble keeps the last dozen, oldest first), in Pebble's words.
    public var changes: [String]
    /// Deletions in the Documents copies Pebble is still checking (conversations and memory entries).
    public var checking: Int
    /// Conversations in Recently deleted, newest first.
    public var recentlyDeleted: [TrashedChat]

    public init(changes: [String] = [], checking: Int = 0, recentlyDeleted: [TrashedChat] = []) {
        self.changes = changes
        self.checking = checking
        self.recentlyDeleted = recentlyDeleted
    }

    public init(json: JSONValue) {
        func count(_ value: JSONValue?) -> Int { max(0, value?.int ?? 0) }
        let waiting = json["documents"]?["pending"]?["waiting"]
        self.init(
            changes: (json["events"]?.array ?? []).compactMap { $0["text"]?.string }.filter { !$0.isEmpty }.reversed(),
            checking: count(waiting?["conversations"]) + count(waiting?["memory"]),
            recentlyDeleted: (json["recently_deleted"]?.array ?? []).compactMap(TrashedChat.init(json:)))
    }
}

/// What "Delete all conversations" or "Delete all now" did (`storage_trash_all`, `storage_purge_all`).
public struct ConversationsRemoved: Sendable, Hashable {
    /// Moved to Recently deleted, or deleted for good.
    public var count: Int
    /// The ones Pebble kept: a running task or an active schedule uses it, or its own checks refused.
    public var kept: Int

    public init(count: Int, kept: Int = 0) {
        self.count = count
        self.kept = kept
    }
}

// MARK: - Settings › Privacy & Stealth: usage telemetry (SS-03, SS-06)

/// Pebble's opt-in usage log, as its Settings read it (`telemetry_get`, and `telemetry_set`'s answer): kept only on
/// the Mac, never uploaded. Counts read as zero unless they are whole, non-negative numbers (TelemetrySettings.vue
/// `count`); the notice is Pebble's text, shown literally.
public struct TelemetryStatus: Sendable, Hashable {
    /// What one kind of event can hold, in words ("run settled": "approvals, input tokens log2, …").
    public struct Field: Sendable, Hashable, Identifiable {
        public var kind: String
        public var names: [String]
        public var id: String { kind }
    }

    public var enabled: Bool
    public var consentedAt: Date?
    /// The notice's version, sent back when turning it on; empty when Pebble gave none (then it can't be turned on).
    public var consentVersion: String
    public var notice: String
    /// The log's random ID while it is on.
    public var installID: String?
    public var events: Int
    public var dropped: Int
    public var expired: Int
    public var refused: Int
    /// The most it keeps: events, kilobytes and days.
    public var maxEvents: Int
    public var maxKilobytes: Int
    public var retentionDays: Int
    public var fields: [Field]

    public init(
        enabled: Bool = false, consentedAt: Date? = nil, consentVersion: String = "", notice: String = "",
        installID: String? = nil, events: Int = 0, dropped: Int = 0, expired: Int = 0, refused: Int = 0,
        maxEvents: Int = 0, maxKilobytes: Int = 0, retentionDays: Int = 0, fields: [Field] = []
    ) {
        self.enabled = enabled
        self.consentedAt = consentedAt
        self.consentVersion = consentVersion
        self.notice = notice
        self.installID = installID
        self.events = events
        self.dropped = dropped
        self.expired = expired
        self.refused = refused
        self.maxEvents = maxEvents
        self.maxKilobytes = maxKilobytes
        self.retentionDays = retentionDays
        self.fields = fields
    }

    /// Nil unless Pebble's answer says whether it is on (the Mac's `accept` takes only such an answer).
    public init?(json: JSONValue) {
        guard json.object?["enabled"] != nil else { return nil }
        func count(_ value: JSONValue?) -> Int {
            guard let number = value?.double, number.isFinite, number >= 0 else { return 0 }
            return Int(number.rounded(.down))
        }
        let limits = json["limits"]
        let fields = (json["fields"]?.object ?? [:]).map { kind, names in
            Field(
                kind: kind.replacingOccurrences(of: "_", with: " "),
                names: (names.array ?? []).compactMap(\.string).map { $0.replacingOccurrences(of: "_", with: " ") })
        }
        self.init(
            enabled: json["enabled"]?.bool == true, consentedAt: unixDate(json["consented_at"]),
            consentVersion: json["current_consent_version"]?.string ?? "", notice: json["consent_text"]?.string ?? "",
            installID: json["install_id"]?.string, events: count(json["events"]), dropped: count(json["dropped"]),
            expired: count(json["expired"]), refused: count(json["refused"]), maxEvents: count(limits?["max_events"]),
            maxKilobytes: Int((Double(count(limits?["max_bytes"])) / 1024).rounded()),
            retentionDays: count(limits?["retention_days"]),
            fields: fields.sorted { $0.kind < $1.kind })
    }
}

// MARK: - Settings › Permissions: Pebble's Shell (SP-14)

/// A website or folder Pebble's Shell may use without asking (`shell_grants`: `{hosts: {site: scope}, folders: {path:
/// scope}}`), saved for good ("always") or until Pebble quits.
public struct ShellGrant: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        /// A website the Shell's commands may reach.
        case site = "hosts"
        /// A folder the Shell's commands may write in.
        case folder = "folders"
    }

    public var kind: Kind
    /// The site's name or the folder's path, as Pebble keeps it.
    public var value: String
    /// Saved for good; otherwise allowed until Pebble quits.
    public var always: Bool
    public var id: String { kind.rawValue + "\u{0}" + value }

    public init(kind: Kind, value: String, always: Bool) {
        self.kind = kind
        self.value = value
        self.always = always
    }

    /// Pebble's grants: websites first, then folders (the Mac's order), each alphabetical. A value that isn't text is
    /// left out; a scope other than "always" reads as until Pebble quits, as the Mac reads it.
    public static func list(json: JSONValue) -> [ShellGrant] {
        [Kind.site, .folder].flatMap { kind in
            (json[kind.rawValue]?.object ?? [:]).filter { !$0.key.isEmpty }
                .map { ShellGrant(kind: kind, value: $0.key, always: $0.value.string == "always") }
                .sorted { $0.value < $1.value }
        }
    }
}

// MARK: - Settings › General: notification delivery per schedule (SG-13)

/// What became of the Mac's banners, and each schedule's banners on or muted (`notification_status`), as the Mac's
/// Delivery block reads them: a count that isn't a whole number reads as zero, and a schedule without its id, name or
/// muted state is left out.
public struct NotificationDelivery: Sendable, Hashable {
    public struct Schedule: Sendable, Hashable, Identifiable {
        public var jobID: String
        public var chatID: ChatID?
        /// The schedule's name.
        public var label: String
        public var muted: Bool
        public var id: String { jobID }

        public init(jobID: String, chatID: ChatID? = nil, label: String, muted: Bool) {
            self.jobID = jobID
            self.chatID = chatID
            self.label = label
            self.muted = muted
        }
    }

    public var waiting: Int
    public var shown: Int
    public var notShown: Int
    public var failed: Int
    /// Waiting banners held for quiet hours.
    public var heldForQuietHours: Int
    public var quietHoursNow: Bool
    /// Pebble's code for the last banner that couldn't be shown, if any.
    public var lastProblem: String?
    public var schedules: [Schedule]

    public init(
        waiting: Int = 0, shown: Int = 0, notShown: Int = 0, failed: Int = 0, heldForQuietHours: Int = 0,
        quietHoursNow: Bool = false, lastProblem: String? = nil, schedules: [Schedule] = []
    ) {
        self.waiting = waiting
        self.shown = shown
        self.notShown = notShown
        self.failed = failed
        self.heldForQuietHours = heldForQuietHours
        self.quietHoursNow = quietHoursNow
        self.lastProblem = lastProblem
        self.schedules = schedules
    }

    public init(json: JSONValue) {
        func whole(_ value: JSONValue?) -> Int {
            guard let number = value?.double, number.isFinite, number == number.rounded() else { return 0 }
            return Int(number)
        }
        let outbox = json["outbox"]
        let schedules = (json["jobs"]?.array ?? []).compactMap { job -> Schedule? in
            guard let id = job["job_id"]?.string, let label = job["label"]?.string, let muted = job["muted"]?.bool
            else { return nil }
            return Schedule(jobID: id, chatID: job["chat_id"]?.string, label: label, muted: muted)
        }
        let problem = json["last_failure"]?["reason"]
        self.init(
            waiting: whole(outbox?["pending"]), shown: whole(outbox?["delivered"]),
            notShown: whole(outbox?["suppressed"]), failed: whole(outbox?["failed"]),
            heldForQuietHours: whole(json["deferred"]), quietHoursNow: json["quiet_now"]?.bool == true,
            lastProblem: json["last_failure"]?.object == nil ? nil : (problem?.string ?? ""), schedules: schedules)
    }
}

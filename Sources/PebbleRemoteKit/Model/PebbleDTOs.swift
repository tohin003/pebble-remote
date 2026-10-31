import Foundation
import PebbleProtocol

// Pebble's payloads as the phone reads them, decoded tolerantly from JSONValue: unknown fields are ignored, optional
// fields may be missing, and a record without the field that identifies it (its id) yields nil instead of an error.
// Ground truth (read-only Pebble checkout): src/types.ts; backend/pebble/app.py state(), chat(), send(), the `remote.*`
// methods in the bridge contract 3.8; store.py, runtime.py Runs.list, interaction.py question().
// Pebble's times are Unix seconds (REAL).

/// A conversation row: one of state().chats (SELECT * FROM chats), or the head of get_chat.
public struct ChatDTO: Sendable, Hashable {
    public var id: ChatID
    public var title: String
    /// The project folder, if the conversation has one.
    public var workspace: String?
    public var updated: Date?
    /// In Recently deleted.
    public var trashed: Bool

    public init(id: ChatID, title: String, workspace: String? = nil, updated: Date? = nil, trashed: Bool = false) {
        self.id = id
        self.title = title
        self.workspace = workspace
        self.updated = updated
        self.trashed = trashed
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty else { return nil }
        self.init(
            id: id, title: json["title"]?.string ?? "", workspace: json["workspace"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            updated: unixDate(json["updated"]), trashed: json["trashed"]?.bool ?? false)
    }

    /// The project's name: the folder's last path component.
    public var project: String? {
        guard let workspace else { return nil }
        let name = workspace.split(separator: "/").last.map(String.init)
        return name?.isEmpty == false ? name : nil
    }
}

/// A run's per-run counts (get_chat, settled runs only).
public struct RunCountsDTO: Sendable, Hashable {
    public var steps: Int
    public var retries: Int
    public var waited: Double

    public init?(json: JSONValue?) {
        guard let json, let steps = json["steps"]?.int, let retries = json["retries"]?.int,
            let waited = json["waited"]?.double, steps >= 0, retries >= 0, waited >= 0
        else { return nil }
        self.steps = steps
        self.retries = retries
        self.waited = waited
    }
}

/// A run: one of state().runs or get_chat's runs (Runs.list: id, chat_id, state, steps, elapsed, error, created,
/// updated; get_chat adds counts).
public struct RunDTO: Sendable, Hashable {
    public var id: RunID
    public var chatID: ChatID?
    public var state: RunState
    public var steps: Int?
    /// The run's active seconds (waits for the person left out).
    public var elapsed: Double?
    /// Pebble's note on how it ended; written partly for the model (see PersonNote).
    public var error: String?
    public var created: Date?
    public var updated: Date?
    public var counts: RunCountsDTO?

    public init(
        id: RunID, chatID: ChatID?, state: RunState, steps: Int? = nil, elapsed: Double? = nil, error: String? = nil,
        created: Date? = nil, updated: Date? = nil, counts: RunCountsDTO? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.state = state
        self.steps = steps
        self.elapsed = elapsed
        self.error = error
        self.created = created
        self.updated = updated
        self.counts = counts
    }

    public init?(json: JSONValue, chatID fallback: ChatID? = nil) {
        guard let id = json["id"]?.string, !id.isEmpty, let state = json["state"]?.string else { return nil }
        self.init(
            id: id, chatID: json["chat_id"]?.string ?? fallback, state: RunState(rawValue: state),
            steps: json["steps"]?.int, elapsed: json["elapsed"]?.double, error: json["error"]?.string,
            created: unixDate(json["created"]), updated: unixDate(json["updated"]), counts: RunCountsDTO(json: json["counts"]))
    }
}

/// A stored message (get_chat messages, a question event's `message`). Only the person's and Pebble's messages.
public struct MessageDTO: Sendable, Hashable {
    public var id: MessageID
    public var role: MessageItem.Role
    public var content: String
    public var created: Date?
    /// The run that wrote this reply (assistant messages of settled runs).
    public var runID: RunID?
    /// Photos and files sent with it.
    public var attachments: [AttachmentRef]

    public init?(json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty, let roleText = json["role"]?.string,
            let role = MessageItem.Role(rawValue: roleText), let content = json["content"]?.string
        else { return nil }
        self.id = id
        self.role = role
        self.content = content
        created = unixDate(json["created"])
        runID = json["run_id"]?.string
        attachments = (json["attachments"]?.array ?? []).compactMap(AttachmentRef.init(json:))
    }
}

/// A card: a row of Pebble's actions table (store.actions), as get_chat and the `actions` event carry it.
public struct ActionDTO: Sendable, Hashable {
    public var id: ActionID
    public var chatID: ChatID?
    public var kind: CardKind
    /// pending, running, applied, rejected, failed, expired, superseded, approved, held, undone.
    public var status: String
    public var payload: JSONValue
    public var created: Date?

    public init(id: ActionID, chatID: ChatID?, kind: CardKind, status: String, payload: JSONValue, created: Date?) {
        self.id = id
        self.chatID = chatID
        self.kind = kind
        self.status = status
        self.payload = payload
        self.created = created
    }

    public init?(json: JSONValue, chatID fallback: ChatID? = nil) {
        guard let id = json["id"]?.string, !id.isEmpty, let kind = json["kind"]?.string else { return nil }
        self.init(
            id: id, chatID: json["chat_id"]?.string ?? fallback, kind: CardKind(rawValue: kind),
            status: json["status"]?.string ?? "", payload: json["payload"] ?? .object([:]), created: unixDate(json["created"]))
    }

    /// Waiting for the person's decision.
    public var isPending: Bool { status == "pending" }
}

/// A question Pebble asked (interaction.question(): one to three items, options, always free text).
public struct QuestionDTO: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public struct Option: Sendable, Hashable {
            public var id: String
            public var label: String
            public var description: String?
        }
        public var id: String
        public var title: String
        public var options: [Option]
        public var allowFreeText: Bool
    }

    public var id: QuestionID
    public var runID: RunID?
    public var chatID: ChatID?
    public var revision: Int
    public var required: Bool
    /// pending, answered, cancelled.
    public var status: String
    public var items: [Item]
    public var created: Date?
    /// The child agent that asked, when an agent did.
    public var requesterName: String?

    public init?(json: JSONValue, chatID fallback: ChatID? = nil) {
        guard let id = json["id"]?.string, !id.isEmpty else { return nil }
        self.id = id
        runID = json["run_id"]?.string
        chatID = json["chat_id"]?.string ?? fallback
        revision = json["revision"]?.int ?? 1
        required = json["required"]?.bool ?? (json["required"]?.int).map { $0 != 0 } ?? false
        status = json["status"]?.string ?? "pending"
        items = (json["items"]?.array ?? []).compactMap { item in
            guard let itemID = item["id"]?.string else { return nil }
            let options: [Item.Option] = (item["options"]?.array ?? []).compactMap { option in
                guard let optionID = option["id"]?.string, let label = option["label"]?.string else { return nil }
                let description = option["description"]?.string
                return Item.Option(id: optionID, label: label, description: description?.isEmpty == false ? description : nil)
            }
            return Item(
                id: itemID, title: item["title"]?.string ?? "", options: options,
                allowFreeText: item["allow_free_text"]?.bool ?? true)
        }
        created = unixDate(json["created"])
        requesterName = json["requester_agent_name"]?.string ?? json["requester_agent_id"]?.string
    }

    public var isPending: Bool { status == "pending" }
}

/// The model Pebble uses now (state().model and the `model` event: Model.status() / Providers.status()).
public struct ModelDTO: Sendable, Hashable {
    /// unloaded, loading, ready, error (a cloud route is always ready).
    public var state: String
    public var configured: Bool
    public var name: String?
    public var effort: String?
    public var efforts: [String]
    /// The effort Pebble recommends for this model (its menu marks it "recommended").
    public var defaultEffort: String?
    public var kind: String?
    public var provider: String?
    public var profileID: String?

    public init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        state = json["state"]?.string ?? ""
        configured = json["configured"]?.bool ?? false
        name = json["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        effort = json["effort"]?.string ?? json["default_effort"]?.string
        efforts = (json["efforts"]?.array ?? []).compactMap(\.string)
        defaultEffort = json["default_effort"]?.string
        kind = json["kind"]?.string
        provider = json["provider"]?.string
        profileID = json["profile_id"]?.string
    }

    /// Pebble can answer: a model is connected and has not failed.
    public var isOnline: Bool { configured && state != "error" }
    public var isLoading: Bool { state == "loading" }
}

/// state().settings: the switches the phone shows. `permissions` is kept whole, because Pebble's `setting` accepts
/// only the full object ({mode, tools} with every required group), so changing the mode resends the tools as they are.
public struct SettingsDTO: Sendable, Hashable {
    /// The whole settings object, as Pebble sent it (PebbleSettings reads every key from it).
    public var raw: JSONValue
    public var permissions: JSONValue?
    public var mode: PermissionMode?
    public var fastReplies: FastReplies?
    public var stealth: Bool
    /// Pebble may act in windows the person shares (permissions.tools.screen; off when absent).
    public var screenControl: Bool

    public init(json: JSONValue) {
        raw = json
        let permissions = json["permissions"]
        self.permissions = permissions?.object != nil ? permissions : nil
        mode = permissions?["mode"]?.string.flatMap(PermissionMode.init(rawValue:))
        fastReplies = json["fast_replies"]?.string.flatMap(FastReplies.init(rawValue:))
        stealth = json["stealth"]?.bool ?? false
        screenControl = permissions?["tools"]?["screen"]?.bool ?? false
    }

    /// The permissions object with only the mode changed, ready for `setting {key: "permissions"}`.
    public func permissions(withMode mode: PermissionMode) -> JSONValue? {
        guard var object = permissions?.object else { return nil }
        object["mode"] = .string(mode.rawValue)
        return .object(object)
    }
}

/// state(): what the phone reads on connect and after `settings`, `idle` and the list events.
public struct StateDTO: Sendable, Hashable {
    public var version: String?
    /// Newest activity first; conversations in Recently deleted are already left out by Pebble.
    public var chats: [ChatDTO]
    /// The newest 100 runs across conversations.
    public var runs: [RunDTO]
    /// The conversation and run that hold Pebble's one worker now.
    public var active: ChatID?
    public var activeRun: RunID?
    public var model: ModelDTO?
    public var settings: SettingsDTO
    /// Scheduled-job notices not yet acknowledged.
    public var jobNotifications: Int
    /// Those notices: `[{id, chat_id, title, created}]`.
    public var jobNotices: [JobNotice]
    /// state().memory.types: `[{id, name, count, enabled}]`.
    public var memoryTypes: [JSONValue]

    public init?(json: JSONValue) {
        guard json.object != nil else { return nil }
        version = json["version"]?.string
        chats = (json["chats"]?.array ?? []).compactMap(ChatDTO.init(json:))
        runs = (json["runs"]?.array ?? []).compactMap { RunDTO(json: $0) }
        active = json["active"]?.string
        activeRun = json["active_run"]?.string
        model = json["model"].flatMap(ModelDTO.init(json:))
        settings = SettingsDTO(json: json["settings"] ?? .object([:]))
        jobNotifications = json["job_notifications"]?.array?.count ?? 0
        memoryTypes = json["memory"]?["types"]?.array ?? []
        jobNotices = (json["job_notifications"]?.array ?? []).compactMap { notice in
            guard let id = notice["id"]?.string, let chat = notice["chat_id"]?.string else { return nil }
            return JobNotice(id: id, chatID: chat, title: notice["title"]?.string ?? "", created: unixDate(notice["created"]))
        }
    }
}

/// get_chat, or remote.chat_tail (the same shape with only the newest messages, plus has_older).
public struct ChatDetailDTO: Sendable, Hashable {
    public var chat: ChatDTO
    public var messages: [MessageDTO]
    public var actions: [ActionDTO]
    public var runs: [RunDTO]
    /// Pending questions (chat() lists only those).
    public var questions: [QuestionDTO]
    /// remote.chat_tail: older messages exist before the first one here.
    public var hasOlder: Bool
    /// The conversation's views, oldest first (lane G: pebble-ui-spec v1's native kinds).
    public var artifacts: [PebbleArtifact]

    public init?(json: JSONValue) {
        guard let chat = ChatDTO(json: json) else { return nil }
        self.chat = chat
        messages = (json["messages"]?.array ?? []).compactMap(MessageDTO.init(json:))
        actions = (json["actions"]?.array ?? []).compactMap { ActionDTO(json: $0, chatID: chat.id) }
        runs = (json["runs"]?.array ?? []).compactMap { RunDTO(json: $0, chatID: chat.id) }
        questions = (json["questions"]?.array ?? []).compactMap { QuestionDTO(json: $0, chatID: chat.id) }
        hasOlder = json["has_older"]?.bool ?? false
        artifacts = (json["artifacts"]?.array ?? []).compactMap { PebbleArtifact(json: $0, chatID: chat.id) }
    }
}

/// remote.chat_before: `{messages, has_older}`.
public struct OlderMessagesDTO: Sendable, Hashable {
    public var messages: [MessageDTO]
    public var hasOlder: Bool

    public init?(json: JSONValue) {
        guard let list = json["messages"]?.array else { return nil }
        messages = list.compactMap(MessageDTO.init(json:))
        hasOlder = json["has_older"]?.bool ?? false
    }
}

/// send's answer: a new run (`run_id`), guidance to the live run (`steering`), or a slash command answered at once
/// (`command`: Pebble stored the command and its reply and emitted only `complete`).
public struct SendResultDTO: Sendable, Hashable {
    public var messageID: MessageID?
    public var runID: RunID?
    public var steering: Bool
    public var command: Bool

    public init(json: JSONValue) {
        messageID = json["message_id"]?.string
        runID = json["run_id"]?.string
        steering = json["steering"]?.bool ?? false
        command = json["command"]?.bool ?? false
    }
}

/// The Mac as the bridge reports it: `remote.mac` events and remote.status's `mac`.
public struct MacDTO: Sendable, Hashable {
    public var name: String?
    public var batteryPercent: Int?
    public var charging: Bool?
    public var onPower: Bool?
    public var keepAwake: Bool?

    public init(json: JSONValue) {
        name = json["name"]?.string
        batteryPercent = json["battery_percent"]?.int
        charging = json["charging"]?.bool
        onPower = json["on_power"]?.bool
        keepAwake = json["keep_awake"]?.bool
    }
}

/// remote.status: `{mac, pebble: {running, version}, bridge: {version, epoch, endpoints}}`.
public struct RemoteStatusDTO: Sendable, Hashable {
    public var mac: MacDTO?
    public var pebbleRunning: Bool?
    public var pebbleVersion: String?
    public var bridgeVersion: String?
    public var endpoints: [Endpoint]

    public init(json: JSONValue) {
        mac = json["mac"].map(MacDTO.init(json:))
        pebbleRunning = json["pebble"]?["running"]?.bool
        pebbleVersion = json["pebble"]?["version"]?.string
        bridgeVersion = json["bridge"]?["version"]?.string
        endpoints = (json["bridge"]?["endpoints"]?.array ?? []).compactMap { $0.string.flatMap(Endpoint.init(parsing:)) }
    }
}

/// A Unix-seconds field as a date.
func unixDate(_ value: JSONValue?) -> Date? {
    guard let seconds = value?.double, seconds.isFinite, seconds > 0 else { return nil }
    return Date(timeIntervalSince1970: seconds)
}

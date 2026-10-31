import Foundation
import PebbleProtocol

// What the screens read. Value types only; RemoteStore builds them from Pebble's state and events.
// Lane A owns this file's evolution; screens (lane E) depend on it, so additions are free and renames go through
// docs/TEAM_BOARD.md first.

public typealias ChatID = String
public typealias RunID = String
public typealias MessageID = String
public typealias ActionID = String
public typealias QuestionID = String

// MARK: - Pairing and connection

/// A Mac this phone is paired with (stored in the Keychain by the security layer).
public struct PairedMac: Sendable, Hashable, Codable, Identifiable {
    public var id: String { bridgeID }
    public var bridgeID: String
    public var name: String
    public var deviceID: String
    /// base64url SHA-256 of the bridge certificate's SubjectPublicKeyInfo; every connection must present it.
    public var pin: String
    public var endpoints: [Endpoint]
    public var pairedAt: Date

    public init(bridgeID: String, name: String, deviceID: String, pin: String, endpoints: [Endpoint], pairedAt: Date) {
        self.bridgeID = bridgeID
        self.name = name
        self.deviceID = deviceID
        self.pin = pin
        self.endpoints = endpoints
        self.pairedAt = pairedAt
    }
}

public struct Endpoint: Sendable, Hashable, Codable, CustomStringConvertible {
    public var host: String
    public var port: UInt16
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
    public var description: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }

    /// How this endpoint reaches the Mac, judged from the address alone.
    public var routeKind: RouteKind {
        let lower = host.lowercased()
        if lower.hasSuffix(".ts.net") { return .tailscale }
        if lower.hasPrefix("100."), let second = lower.split(separator: ".").dropFirst().first.flatMap({ Int($0) }),
            (64...127).contains(second)
        {
            return .tailscale  // 100.64.0.0/10, Tailscale's address range
        }
        if lower.hasSuffix(".local") || lower.hasPrefix("192.168.") || lower.hasPrefix("10.") || lower.hasPrefix("172.")
            || lower.hasPrefix("fe80:")
        {
            return .lan
        }
        return .other
    }
}

public enum RouteKind: String, Sendable, Hashable, Codable, CaseIterable {
    case lan, tailscale, other, demo
}

public enum ConnectionPhase: Sendable, Hashable {
    /// Not paired yet, or stopped on purpose (the app is in the background).
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int, nextTry: Date?)
    /// Needs the person: re-pair, update the bridge, or start Pebble.
    case failed(ConnectionProblem)
}

public enum ConnectionProblem: Sendable, Hashable {
    case revoked
    case unknownDevice
    case pinMismatch
    case bridgeTooOld
    case pebbleNotRunning
    case unreachable
    /// iOS keeps Pebble Remote off the local network (its Local Network switch is off).
    case localNetworkDenied
    case other(String)
}

public struct ConnectionStatus: Sendable, Hashable {
    public var phase: ConnectionPhase
    public var route: RouteKind?
    public var endpoint: Endpoint?
    /// The latest round trip to the Mac and back, in milliseconds.
    public var roundTrip: Double?
    public var since: Date?

    public init(
        phase: ConnectionPhase, route: RouteKind? = nil, endpoint: Endpoint? = nil, roundTrip: Double? = nil,
        since: Date? = nil
    ) {
        self.phase = phase
        self.route = route
        self.endpoint = endpoint
        self.roundTrip = roundTrip
        self.since = since
    }

    public static let idle = ConnectionStatus(phase: .idle)
}

// MARK: - Pebble and the Mac

public struct PebbleOverview: Sendable, Hashable {
    public var version: String
    public var modelName: String?
    public var effort: String?
    /// The efforts the model in use offers, in Pebble's order; one ("default") when it has no effort control.
    public var efforts: [String]
    /// The effort Pebble recommends for the model in use.
    public var defaultEffort: String?
    public var mode: PermissionMode
    public var fastReplies: FastReplies?
    public var stealth: Bool
    /// Pebble may act in windows the person shares (Settings, "screen" tool switch).
    public var screenControl: Bool
    public var modelOnline: Bool
    /// Lane S (SM-10): when the model in use is a model file on the Mac (state().model: kind "gguf", configured), its
    /// state: "unloaded", "loading", "ready" or "error", which Pebble's Rest model and Load now change. Nil otherwise.
    public var localModelState: String?

    public init(
        version: String, modelName: String? = nil, effort: String? = nil, efforts: [String] = [],
        defaultEffort: String? = nil, mode: PermissionMode, fastReplies: FastReplies? = nil, stealth: Bool = false,
        screenControl: Bool = false, modelOnline: Bool = true, localModelState: String? = nil
    ) {
        self.version = version
        self.modelName = modelName
        self.effort = effort
        self.efforts = efforts
        self.defaultEffort = defaultEffort
        self.mode = mode
        self.fastReplies = fastReplies
        self.stealth = stealth
        self.screenControl = screenControl
        self.modelOnline = modelOnline
        self.localModelState = localModelState
    }
}

public struct MacOverview: Sendable, Hashable {
    public var name: String
    public var batteryPercent: Int?
    public var charging: Bool?
    public var onPower: Bool?
    public var keepAwake: Bool
    public var pebbleRunning: Bool

    public init(
        name: String, batteryPercent: Int? = nil, charging: Bool? = nil, onPower: Bool? = nil, keepAwake: Bool = false,
        pebbleRunning: Bool = true
    ) {
        self.name = name
        self.batteryPercent = batteryPercent
        self.charging = charging
        self.onPower = onPower
        self.keepAwake = keepAwake
        self.pebbleRunning = pebbleRunning
    }
}

// MARK: - Conversations

public struct ChatSummary: Sendable, Hashable, Identifiable {
    public var id: ChatID
    public var title: String
    /// The project folder's name (last path component), if the chat has one.
    public var project: String?
    public var updated: Date?
    /// What the chat's newest run is doing, if it is live or waiting.
    public var status: StatusKey?
    /// Cards and questions waiting for the person in this chat.
    public var waitingCount: Int

    public init(
        id: ChatID, title: String, project: String? = nil, updated: Date? = nil, status: StatusKey? = nil,
        waitingCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.updated = updated
        self.status = status
        self.waitingCount = waitingCount
    }
}

/// A run that is working, or waiting for the person.
public struct LiveRun: Sendable, Hashable, Identifiable {
    public var id: RunID
    public var chatID: ChatID
    public var chatTitle: String
    public var state: RunState
    /// The status key to show (StatusCopy turns it into Pebble's words). Never built from progress labels.
    public var status: StatusKey
    /// The latest activity line ("Reading App.vue"), shown under the status, never inside it.
    public var activity: String?
    public var started: Date?
    public var steps: Int?
    /// While reconnecting to the model (`status == .reconnecting`): which try this is, 1 to 99 (StatusCopy's
    /// "Reconnecting (try 2)").
    public var attempt: Int?

    public init(
        id: RunID, chatID: ChatID, chatTitle: String, state: RunState, status: StatusKey, activity: String? = nil,
        started: Date? = nil, steps: Int? = nil, attempt: Int? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.state = state
        self.status = status
        self.activity = activity
        self.started = started
        self.steps = steps
        self.attempt = attempt
    }
}

/// What a finished run did, for its end line (PebbleDesign's RunCopy.endLine): Pebble's own counts, when it kept them.
public struct RunRecap: Sendable, Hashable {
    public var steps: Int?
    public var retries: Int?
    /// Seconds spent waiting for the person.
    public var waitedSeconds: Double?

    public init(steps: Int? = nil, retries: Int? = nil, waitedSeconds: Double? = nil) {
        self.steps = steps
        self.retries = retries
        self.waitedSeconds = waitedSeconds
    }
}

/// Pebble's banner for a conversation whose task ended or waits (Pebble's `reply_banner` event, D134): `title` is
/// Pebble's own words ("Pebble finished", "Pebble needs your review"); `body` is the conversation's title or empty.
public struct ReplyBanner: Sendable, Hashable, Identifiable {
    public var id: String { "\(chatID)/\(runID ?? "")/\(title)" }
    public var chatID: ChatID
    public var runID: RunID?
    public var title: String
    public var body: String

    public init(chatID: ChatID, runID: RunID?, title: String, body: String) {
        self.chatID = chatID
        self.runID = runID
        self.title = title
        self.body = body
    }
}

public struct MessageItem: Sendable, Hashable, Identifiable {
    public enum Role: String, Sendable, Hashable { case user, assistant }
    public var id: MessageID
    public var role: Role
    public var text: String
    public var created: Date?
    /// True while Pebble is still writing this reply.
    public var isStreaming: Bool
    public var runID: RunID?
    /// Photos and files sent with the message.
    public var attachments: [AttachmentRef]

    public init(
        id: MessageID, role: Role, text: String, created: Date? = nil, isStreaming: Bool = false, runID: RunID? = nil,
        attachments: [AttachmentRef] = []
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.created = created
        self.isStreaming = isStreaming
        self.runID = runID
        self.attachments = attachments
    }
}

/// A card Pebble is holding for the person's review.
public struct ReviewItem: Sendable, Hashable, Identifiable {
    public var id: String { "\(chatID)/\(actionID)" }
    public var chatID: ChatID
    public var chatTitle: String
    public var actionID: ActionID
    public var kind: CardKind
    /// One plain sentence: what approving does ("Run npm test in Pebble Remote").
    public var title: String
    /// The exact thing to approve, if there is one (the command, the file, the address).
    public var detail: String?
    public var created: Date?
    /// A card the companion may answer too (a site, a window, bringing a window forward: Pebble's D133 kinds).
    public var isSimple: Bool
    public var payload: JSONValue
    /// Pebble's one plain sentence on what changes and whether it can be undone (CardWords.summary), when it has one.
    public var summary: String?
    /// The approve button's words on Pebble's card ("Run command", "Apply edit").
    public var approveLabel: String?

    public init(
        chatID: ChatID, chatTitle: String, actionID: ActionID, kind: CardKind, title: String, detail: String? = nil,
        created: Date? = nil, isSimple: Bool = false, payload: JSONValue = .null, summary: String? = nil,
        approveLabel: String? = nil
    ) {
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.actionID = actionID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.created = created
        self.isSimple = isSimple
        self.payload = payload
        self.summary = summary
        self.approveLabel = approveLabel
    }
}

/// A question Pebble asked (AskUserQuestion): one or more prompts with options and, sometimes, free text.
public struct QuestionCard: Sendable, Hashable, Identifiable {
    public struct Prompt: Sendable, Hashable, Identifiable {
        public struct Option: Sendable, Hashable, Identifiable {
            public var id: String
            public var label: String
            public var detail: String?
            public init(id: String, label: String, detail: String? = nil) {
                self.id = id
                self.label = label
                self.detail = detail
            }
        }
        public var id: String
        public var title: String
        public var options: [Option]
        public var allowsFreeText: Bool
        public init(id: String, title: String, options: [Option], allowsFreeText: Bool) {
            self.id = id
            self.title = title
            self.options = options
            self.allowsFreeText = allowsFreeText
        }
    }
    public var id: String { "\(chatID)/\(questionID)" }
    public var chatID: ChatID
    public var chatTitle: String
    public var questionID: QuestionID
    public var runID: RunID?
    public var revision: Int
    public var required: Bool
    public var prompts: [Prompt]
    public var created: Date?
    /// The child agent that asked, when an agent did ("Requested by <name>").
    public var requester: String?
    /// The Pebble form this question belongs to, when the phone knows it (lane G): the form is answered in its own
    /// sheet with `artifact_submit`, and the question shows as the form.
    public var form: PebbleArtifact?

    public init(
        chatID: ChatID, chatTitle: String, questionID: QuestionID, runID: RunID?, revision: Int, required: Bool,
        prompts: [Prompt], created: Date? = nil, requester: String? = nil
    ) {
        self.chatID = chatID
        self.chatTitle = chatTitle
        self.questionID = questionID
        self.runID = runID
        self.revision = revision
        self.required = required
        self.prompts = prompts
        self.created = created
        self.requester = requester
    }
}

public enum QuestionAnswer: Sendable, Hashable {
    case option(id: String, text: String? = nil)
    case text(String)
}

/// Everything waiting for the person, across chats (the Reviews tab).
public enum WaitingItem: Sendable, Hashable, Identifiable {
    case review(ReviewItem)
    case question(QuestionCard)
    /// A task Pebble holds for the person's decision: "Pebble's change isn't verified yet." or "One step has an
    /// uncertain outcome." (`TaskAttention.waitsForDecision`).
    case task(TaskAttention)
    public var id: String {
        switch self {
        case .review(let item): "review/\(item.id)"
        case .question(let card): "question/\(card.id)"
        case .task(let task): "task/\(task.id)"
        }
    }
    public var chatID: ChatID {
        switch self {
        case .review(let item): item.chatID
        case .question(let card): card.chatID
        case .task(let task): task.chatID
        }
    }
    /// The conversation's title, for the item's link to it.
    public var chatTitle: String {
        switch self {
        case .review(let item): item.chatTitle
        case .question(let card): card.chatTitle
        case .task(let task): task.chatTitle
        }
    }
}

/// One row of a conversation, in order.
public enum TranscriptItem: Sendable, Hashable, Identifiable {
    case message(MessageItem)
    /// A line of what Pebble did ("Edited App.vue"), grouped under the reply it led to.
    case activity(id: String, runID: RunID?, text: String, status: StatusKey)
    case review(ReviewItem)
    case question(QuestionCard)
    /// A run's end ("Finished in 2 min 05 s", "Stopped", "Hit a problem: ...").
    case runEnd(id: String, runID: RunID, state: RunState, seconds: Double?, note: String?)
    /// A card Pebble already acted on that offers an Undo (or one the person undid), at the end of its turn.
    case action(ActionRecord)
    /// The conversation's task, when its state needs the person (RunPanel's line under the conversation): Resume, a
    /// held task's three decisions, an uncertain step and the windows it paused.
    case task(TaskAttention)
    /// "Continue with the new model", after the person changed the model in this conversation.
    case handoff(HandoffOffer)
    /// A command that is running, or whose outcome Pebble couldn't confirm.
    case command(ProcessJob)

    public var id: String {
        switch self {
        case .message(let message): "m/\(message.id)"
        case .activity(let id, _, _, _): "a/\(id)"
        case .review(let item): "r/\(item.id)"
        case .question(let card): "q/\(card.id)"
        case .runEnd(let id, _, _, _, _): "e/\(id)"
        case .action(let record): "x/\(record.id)"
        case .task(let task): "t/\(task.id)"
        case .handoff(let offer): "h/\(offer.id)"
        case .command(let job): "p/\(job.id)"
        }
    }
}

// MARK: - Folders on the Mac (proposal v0.5: "Connect a project" without the Mac's folder picker)

/// One folder on the Mac, as `remote.folders` lists it: its name and path, never its files.
public struct FolderEntry: Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var name: String
    /// The folder's full path on the Mac.
    public var path: String
    /// The folder holds `.git` (a Git repository).
    public var isProject: Bool

    public init(name: String, path: String, isProject: Bool = false) {
        self.name = name
        self.path = path
        self.isProject = isProject
    }
}

/// The subfolders of one folder on the Mac (`remote.folders`): inside the home folder only, without hidden folders or
/// the folders Pebble protects, sorted by name, at most 500.
public struct FolderListing: Sendable, Hashable {
    /// The home folder on the Mac.
    public var home: String
    /// The folder listed.
    public var path: String
    /// The folder above it; nil at the home folder.
    public var parent: String?
    public var folders: [FolderEntry]

    public init(home: String, path: String, parent: String?, folders: [FolderEntry]) {
        self.home = home
        self.path = path
        self.parent = parent
        self.folders = folders
    }

    /// The listed folder's own name.
    public var name: String { ProjectRef.folderName(path) }
    /// The home folder itself, which Pebble refuses as a project ("Choose a project folder rather than your home
    /// folder or disk root.").
    public var isHome: Bool { path == home }
}

/// A photo, file or web page waiting in a new conversation that isn't on the Mac yet (a draft). It stays on the phone
/// until the first message is sent, then goes to Pebble with it.
public struct DraftAttachment: Sendable, Hashable, Identifiable {
    public enum Source: Sendable, Hashable {
        /// A photo or file's bytes, sent with `attach_bytes`.
        case bytes(Data)
        /// A web page's address, read by Pebble with `attach_url`.
        case webPage(String)
    }

    public var id: String
    /// The file's name, or the page's address.
    public var name: String
    public var source: Source
    /// A small JPEG of a photo, for the screen.
    public var preview: Data?

    public init(id: String = UUID().uuidString, name: String, source: Source, preview: Data? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.preview = preview
    }

    /// As the conversation shows attachments: "image", "file" or "url".
    public var ref: AttachmentRef {
        switch source {
        case .bytes(let data):
            AttachmentRef(id: id, name: name, kind: preview == nil ? "file" : "image", preview: preview, bytes: data.count)
        case .webPage:
            AttachmentRef(id: id, name: name, kind: "url")
        }
    }
}

/// A refusal or failure in Pebble's own words, shown once.
public struct PersonFacingError: Error, Sendable, Hashable, Identifiable {
    public var id: UUID = UUID()
    public var message: String
    /// Pebble's or the bridge's content-free code ("trashed_conversation", "not_allowed", "proof_required").
    public var code: String?
    public init(message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }
}

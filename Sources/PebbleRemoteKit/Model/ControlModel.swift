import Foundation
import PebbleProtocol

// What the Control tab, Settings and the conversation details read (contract v0.2, R2 widened: the phone controls what
// the Mac's main window can). Value types only; RemoteStore builds them from Pebble's answers. Additions are free;
// renames go through docs/TEAM_BOARD.md first.

/// A project: a folder on the Mac that conversations work in. Usually one Pebble already knows (the folder of one or
/// more conversations); a folder chosen with "Connect a project" (`FolderEntry`) becomes one when a conversation
/// starts in it.
public struct ProjectRef: Sendable, Hashable, Identifiable {
    public var id: String { path }
    /// The folder on the Mac, as Pebble stores it (`workspace`).
    public var path: String
    /// Its last path component.
    public var name: String
    /// The newest activity in one of its conversations.
    public var lastUsed: Date?

    public init(path: String, name: String, lastUsed: Date? = nil) {
        self.path = path
        self.name = name
        self.lastUsed = lastUsed
    }

    /// A folder on the Mac, named by its last path component.
    public init(folder path: String) {
        self.init(path: path, name: Self.folderName(path))
    }

    /// A folder from `remote.folders`.
    public init(_ folder: FolderEntry) {
        self.init(path: folder.path, name: folder.name)
    }

    /// A folder's name: the path's last component (as Pebble's window shows it, `split(/[\\/]/).pop()`).
    public static func folderName(_ path: String) -> String {
        let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
        return name?.isEmpty == false ? name! : path
    }
}

/// One of Pebble's model profiles (`model_profiles`), with the efforts it offers.
public struct ModelChoice: Sendable, Hashable, Identifiable {
    public var id: String
    /// The name to show (Pebble's display name, else its model, else its profile name).
    public var name: String
    /// The provider or route ("ChatGPT", "Local").
    public var provider: String?
    public var isLocal: Bool
    /// Efforts this model offers, in Pebble's order ("low", "medium", "high"); empty when it has none.
    public var efforts: [String]

    public init(id: String, name: String, provider: String? = nil, isLocal: Bool = false, efforts: [String] = []) {
        self.id = id
        self.name = name
        self.provider = provider
        self.isLocal = isLocal
        self.efforts = efforts
    }
}

/// Every switch in Pebble's settings (state().settings), for the Settings screens.
public struct PebbleSettings: Sendable, Hashable {
    /// "system", "light" or "dark".
    public var theme: String
    public var reducedMotion: Bool
    public var stealth: Bool
    public var memoryEnabled: Bool
    /// One switch per memory layer: working, episodic, semantic, procedural, temporal, profile.
    public var memoryLayers: [String: Bool]
    public var mode: PermissionMode
    /// The permission groups' switches: files, edits, tests, apps, web, terminal, plugins, views, screen, capture.
    public var tools: [String: Bool]
    public var fastReplies: FastReplies?
    /// The companion's presentation switches: pointer, reactions, status_words ("rotate", "fixed", "off"), ui_guidance.
    public var companion: JSONValue
    /// The Git actions that are the person's decision (Pebble's `git_decisions`), as Pebble reports them.
    public var gitDecisions: JSONValue

    public init(
        theme: String = "system", reducedMotion: Bool = false, stealth: Bool = false, memoryEnabled: Bool = true,
        memoryLayers: [String: Bool] = [:], mode: PermissionMode = .ask, tools: [String: Bool] = [:],
        fastReplies: FastReplies? = nil, companion: JSONValue = .null, gitDecisions: JSONValue = .null
    ) {
        self.theme = theme
        self.reducedMotion = reducedMotion
        self.stealth = stealth
        self.memoryEnabled = memoryEnabled
        self.memoryLayers = memoryLayers
        self.mode = mode
        self.tools = tools
        self.fastReplies = fastReplies
        self.companion = companion
        self.gitDecisions = gitDecisions
    }
}

/// One item of a run's activity (Pebble's `run_activity`, activity.ts ActivityItem): what Pebble did, in order.
public struct RunActivityItem: Sendable, Hashable, Identifiable {
    public var id: Int { seq }
    public var seq: Int
    /// Seconds since the run started.
    public var at: Double
    /// context, model, reasoning, tool, retry, approval, child, check, note.
    public var kind: String
    public var label: String
    public var detail: String?
    public var duration: Double?
    /// running, done or failed.
    public var status: String
    /// Pebble's activity class (reading, editing, ...), when it sent one: a status key, never built from the label.
    public var activity: StatusKey?
    /// The step drawn as a card (pebble-ui-spec v1, lane G); nil when Pebble sent none, or one this version doesn't
    /// know (the item then shows its label and detail).
    public var view: WorkView?
    /// Pebble sent a view this version can't draw: the line says "Update the app to see this view" (rule 1).
    public var hasUnreadableView = false

    public init(
        seq: Int, at: Double, kind: String, label: String, detail: String? = nil, duration: Double? = nil,
        status: String, activity: StatusKey? = nil, view: WorkView? = nil
    ) {
        self.seq = seq
        self.at = at
        self.kind = kind
        self.label = label
        self.detail = detail
        self.duration = duration
        self.status = status
        self.activity = activity
        self.view = view
    }
}

/// A run in detail: its record and what it did.
public struct RunDetails: Sendable, Hashable, Identifiable {
    public var id: RunID { run.id }
    public var run: LiveRunRecord
    public var items: [RunActivityItem]
    /// Pebble's reasoning summary, when it sent one.
    public var reasoning: String?
    /// The plan's progress, the run's state and its time (pebble-ui-spec v1's header, lane G).
    public var header: WorkHeader?
    /// The settled run's receipt in counts (pebble-ui-spec v1's summary); nil while it works or waits.
    public var summary: WorkSummary?

    public init(
        run: LiveRunRecord, items: [RunActivityItem], reasoning: String? = nil, header: WorkHeader? = nil,
        summary: WorkSummary? = nil
    ) {
        self.run = run
        self.items = items
        self.reasoning = reasoning
        self.header = header
        self.summary = summary
    }
}

/// A run's record as Pebble keeps it (run_get / run_list), for the details screen.
public struct LiveRunRecord: Sendable, Hashable, Identifiable {
    public var id: RunID
    public var chatID: ChatID?
    public var state: RunState
    public var steps: Int?
    /// Active seconds (waits for the person left out).
    public var elapsed: Double?
    /// Pebble's note on how it ended, kept to the sentences meant for the person.
    public var note: String?
    public var created: Date?
    public var updated: Date?
    /// What the person asked for, when Pebble reports it.
    public var goal: String?

    public init(
        id: RunID, chatID: ChatID? = nil, state: RunState, steps: Int? = nil, elapsed: Double? = nil, note: String? = nil,
        created: Date? = nil, updated: Date? = nil, goal: String? = nil
    ) {
        self.id = id
        self.chatID = chatID
        self.state = state
        self.steps = steps
        self.elapsed = elapsed
        self.note = note
        self.created = created
        self.updated = updated
        self.goal = goal
    }
}

/// A phone paired with the Mac (`remote.devices`).
public struct MacDevice: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var pairedAt: Date?
    public var lastSeen: Date?
    /// This phone.
    public var isCurrent: Bool

    public init(id: String, name: String, pairedAt: Date? = nil, lastSeen: Date? = nil, isCurrent: Bool = false) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
        self.isCurrent = isCurrent
    }
}

/// A picture of the Mac's screens (`remote.screenshot`, contract C3). Never saved on the phone.
public struct MacScreenshot: Sendable, Hashable {
    public struct Display: Sendable, Hashable, Identifiable {
        public var id: Int { index }
        public var index: Int
        public var width: Int
        public var height: Int
        /// "jpeg".
        public var format: String
        /// The image's bytes.
        public var data: Data

        public init(index: Int, width: Int, height: Int, format: String, data: Data) {
            self.index = index
            self.width = width
            self.height = height
            self.format = format
            self.data = data
        }
    }

    public var takenAt: Date?
    public var displays: [Display]

    public init(takenAt: Date?, displays: [Display]) {
        self.takenAt = takenAt
        self.displays = displays
    }
}

/// One of Pebble's six memory layers, with its name in Pebble's words and whether learning and recall use it.
public struct MemoryLayer: Sendable, Hashable, Identifiable {
    /// working, episodic, semantic, procedural, temporal, profile.
    public var id: String
    /// "Working context", "Past experiences", ...
    public var name: String
    /// How many memories it holds, when Pebble says.
    public var count: Int?
    public var isOn: Bool

    public init(id: String, name: String, count: Int? = nil, isOn: Bool = true) {
        self.id = id
        self.name = name
        self.count = count
        self.isOn = isOn
    }

    /// Pebble's names for the layers (backend/pebble/memory.py KINDS), in Pebble's order, for a Pebble that does not
    /// send them in `state().memory.types`.
    public static let pebbleNames: [(id: String, name: String)] = [
        ("working", "Working context"), ("episodic", "Past experiences"), ("semantic", "Facts & knowledge"),
        ("procedural", "Procedures"), ("temporal", "Time-sensitive information"), ("profile", "Your preferences"),
    ]
}

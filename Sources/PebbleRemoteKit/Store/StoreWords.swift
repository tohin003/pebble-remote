import Foundation

/// The few sentences RemoteStore writes itself. Everything else it shows is Pebble's or the bridge's own words
/// (refusals pass through as Pebble wrote them) or PebbleDesign's copy. Plain words in Pebble's voice; PebbleDesign's
/// banned-word check scans this file.
public enum StoreWords {
    public static let notConnected = "Pebble Remote isn't connected to your Mac right now. It reconnects on its own."
    public static let timedOut = "Your Mac didn't answer in time. Try again."
    public static let connectionDropped = "The connection to your Mac dropped. Try again."
    public static let notOffered = "Pebble on your Mac doesn't offer this yet. Update Pebble, then try again."
    public static let settingsNotRead = "Pebble Remote hasn't read Pebble's settings yet. Try again in a moment."
    public static let unreadableAnswer = "Pebble answered in a way this version of Pebble Remote can't read."
    public static let keyNotKept = "Pebble Remote couldn't keep the pairing on this iPhone. Pair again."

    /// What Face ID says for an approval. Titles and names come from Pebble (a card's title can be a model's words),
    /// so each is one plain line of at most `faceIDDetailLength` characters (security review 2026-10-30, S-08).
    public static func approveReason(_ title: String) -> String { "Approve: \(detail(title))" }
    /// What Face ID says before the permission mode changes.
    public static let permissionsReason = "Change Pebble's permissions"
    /// What Face ID says when the phone unlocks acting on the Mac (contract C1).
    public static let unlockReason = "Let this iPhone act on your Mac"
    /// What Face ID says before another setting the bridge guards changes.
    public static let settingReason = "Change Pebble's settings"
    /// What Face ID says before the Mac stays awake on battery.
    public static let keepAwakeReason = "Keep your Mac awake on battery"
    /// What Face ID says before another iPhone is removed from the Mac (Paired iPhones › Remove): Pebble's bridge wants a
    /// proof for it (security review X-8). The name is the phone's, as the Mac lists it.
    public static func removePhoneReason(_ name: String) -> String {
        let shown = detail(name)
        return shown.isEmpty ? "Remove an iPhone from your Mac" : "Remove \u{201C}\(shown)\u{201D} from your Mac"
    }
    /// What Face ID says before a schedule is made or resumed, and before a conversation is deleted for good.
    public static func createScheduleReason(_ name: String) -> String {
        "Create the schedule \u{201C}\(detail(name))\u{201D}"
    }
    public static func resumeScheduleReason(_ name: String) -> String {
        "Resume the schedule \u{201C}\(detail(name))\u{201D}"
    }
    public static func purgeReason(_ title: String) -> String { "Delete \u{201C}\(detail(title))\u{201D} for good" }
    /// What Face ID says before Pebble may work in a folder no conversation used before (proposal v0.5): connecting a
    /// project widens what Pebble may read. The words are Pebble's menu item, then the folder.
    public static func connectProjectReason(_ folder: String) -> String { "Connect a project: \(detail(folder))" }
    /// What Face ID says, should the bridge ask, before a conversation moves to a project (named) or to Companion.
    public static func workspaceReason(_ folder: String?) -> String {
        folder.map(connectProjectReason) ?? "Move this conversation to Companion"
    }
    /// What Face ID says before a terminal command goes to Pebble's review (the composer's "Terminal command").
    public static func terminalCommandReason(_ command: String) -> String { "Terminal command: \(detail(command))" }
    /// Pebble's own words (sources.py `check_url`) for an address it doesn't read.
    public static let webAddressRefused = "Enter a public https:// URL without credentials or a custom port."
    /// Pebble's own words (attachments.py) for an eleventh attachment.
    public static let tooManyAttachments = "Use up to ten attachments per message."

    // MARK: A new folder on the Mac (proposal v0.6, "New Folder" in Connect a project)

    /// What Face ID says before Pebble makes a folder on the Mac: it writes to the Mac's disk. The Files app's words,
    /// then the name.
    public static func createFolderReason(_ name: String) -> String { "Create a folder: \(detail(name))" }
    /// The words for a name no folder can have. The bridge says the same when a name reaches it, and the phone says
    /// them first, so a name that can't work never asks for Face ID.
    public static let folderNameEmpty = "Enter a name for the folder."
    public static let folderNameTooLong = "That name is too long. Use a shorter one."
    public static let folderNameSeparator = "A folder name can't contain / or :."
    public static let folderNameControl = "A folder name can't contain line breaks or other control characters."
    public static let folderNameDot = "A folder name can't start with a dot, which would make it a hidden folder."

    // MARK: Finishing and recovering a task (lane R). Face ID's sentences name the action as Pebble's button does.

    /// Before a held task is kept without verification (Pebble records that the person decided).
    public static func acceptUnverifiedReason(_ title: String) -> String { "Accept as unverified: \(detail(title))" }
    /// Before Pebble repairs a held task once more.
    public static func finishTaskReason(_ title: String) -> String { "Ask Pebble to finish: \(detail(title))" }
    /// Should the bridge ask, before Pebble proposes a held task's tests for review.
    public static func runTestsReason(_ title: String) -> String { "Run the tests: \(detail(title))" }
    /// Should the bridge ask, before a stopped task resumes.
    public static func resumeReason(_ title: String) -> String { "Resume: \(detail(title))" }
    /// Should the bridge ask, before an uncertain outcome is settled or reported.
    public static func settleReason(_ title: String) -> String { "Settle an outcome: \(detail(title))" }
    /// Before an Undo puts files back. The title is the card's ("Change App.vue").
    public static func undoReason(_ title: String) -> String { "Undo: \(detail(title))" }
    /// Should the bridge ask, before Pebble prepares a Git undo for review.
    public static func proposeUndoReason(_ title: String) -> String { "Propose undo: \(detail(title))" }
    /// Before "Always allow" saves a card's hosts and folders for good, then approves the card once.
    public static func alwaysAllowReason(_ title: String) -> String { "Always allow: \(detail(title))" }
    /// Before the person types into a running command, or the phone reads whether it takes typing.
    public static let typeIntoCommandReason = "Type into the command"
    /// Should the bridge ask, before a running command is stopped or an inspection is recorded.
    public static let stopCommandReason = "Stop command"
    public static let inspectCommandReason = "Record my inspection"
    public static let forgetOutputReason = "Forget saved command output"
    /// Before Pebble may send a conversation to another model.
    public static let approveHandoffReason = "Approve this handoff"
    /// Should the bridge ask, before the approved handoff starts its new run.
    public static let startHandoffReason = "Start the new run"

    /// Pebble's window's own words when a handoff's answers don't hold together (ModelHandoff.vue).
    public static let handoffNotPrepared = "Pebble could not prepare this handoff. Nothing was sent."
    public static let handoffNotApproved = "Pebble did not confirm approval of this exact handoff. Nothing was sent."
    public static let handoffNoRun =
        "Pebble did not report a new run. Check this conversation\u{2019}s tasks before reviewing the handoff again."

    /// The longest title or name a Face ID sentence quotes, in characters.
    public static let faceIDDetailLength = 60

    static func detail(_ text: String) -> String { DisplayText.line(text, limit: faceIDDetailLength) }
    /// Pebble's own words (src/bridge.ts) for a file over its 50 MB limit.
    public static let fileTooLarge = "Use a file smaller than 50 MB."

    // MARK: Lane Z: Settings › Memory

    /// What Face ID says before a memory is forgotten for good: the Mac's button label, then the memory's first words.
    public static func forgetMemoryReason(_ text: String) -> String { "Forget this memory: \(detail(text))" }
    /// What Face ID says, should the bridge ask, before a contested memory is decided ("Keep this memory?").
    public static func decideMemoryReason(_ question: String) -> String { detail(question) }

    // MARK: A reply's source markers ([S7]), in Pebble's window's words (App.vue `openCitation`)

    public static func sourceNotRecorded(_ id: String) -> String { "Pebble has no record of \(id) for this reply." }
    /// A source without a web address to open, named instead (its title, its site or its address, up to 80 characters).
    public static func sourceNamed(_ id: String, _ name: String) -> String { "\(id) is \(name)." }
    public static func sourceWithoutAddress(_ id: String) -> String { "\(id) has no web address to open." }
    public static func sourceNotOpened(_ id: String) -> String { "Pebble couldn't open \(id)." }

    /// Content-free codes for the failures above, so screens can tell them apart.
    public enum Code {
        public static let notConnected = "not_connected"
        public static let timedOut = "timed_out"
        public static let transport = "connection_dropped"
        public static let notOffered = "not_offered"
        public static let unreadable = "unreadable"
    }
}

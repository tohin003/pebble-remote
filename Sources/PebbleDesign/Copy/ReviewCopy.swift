import PebbleProtocol

/// The words of Pebble's review cards: what kind of step it is, its state, and the one plain sentence that says
/// what approving does. Ported from Pebble's `src/App.vue` (`ACTION_STATES`, `actionLead`, the card headings) and
/// `src/components/ActionReview.vue` (`labels`), word for word where Pebble has the words. Lane A builds a card's
/// `title` from `lead...` and its `detail` from the exact thing (command, path, address).
nonisolated public enum ReviewCopy {
    /// A short name for the kind of step, shown above the card's sentence.
    public static func kindLabel(_ kind: CardKind) -> String {
        switch kind {
        // ActionReview.vue `labels`, word for word
        case .git: "Reviewed Git plan"
        case .worktree: "Child worktree action"
        case .install: "Dependency install plan"
        case .tests: "Test recipe plan"
        case .command: "Command plan"
        case .shell: "Shell command"
        case .file: "File change"
        case .screen: "Action in an app window"
        case .screenGrant: "Use of an app window"
        case .url: "Web address"
        case .screenRaise: "Bring a window forward"
        case .appAction: "App action"
        case .browserGrant: "Sites in your browser"
        // Pebble shows these three by their heading alone; the phone names them the same way.
        case .edit: "Project edit"
        case .app: "Open an app"
        case .plugin: "Connector call"
        default: "Action"
        }
    }

    /// `ACTION_STATES`: a card's state in words. Unknown states read with spaces for underscores, as Pebble does.
    public static func state(_ status: String) -> String {
        switch status {
        case "pending": "Needs your review"
        case "applied": "Done"
        case "rejected": "Not allowed"
        case "undone": "Undone"
        case "running": "Running"
        case "failed": "Failed"
        case "expired": "Expired"
        case "superseded": "Replaced"
        case "approved": "Approved"
        case "held": "Held by Pebble, not run"
        default: status.replacingOccurrences(of: "_", with: " ")
        }
    }

    // MARK: Leads: what approving does, in one or two plain sentences (App.vue `actionLead`)

    /// An edit to a project file. `newFile` when the file does not exist yet. `scopeReview` is Pebble's own reason a
    /// test-file change waits (shown first).
    public static func leadEdit(newFile: Bool, scopeReview: String? = nil) -> String {
        let lead =
            newFile
            ? "Creates this file in your project. You can undo it afterwards."
            : "Changes this file in your project. You can undo it afterwards."
        if let scopeReview, !scopeReview.isEmpty { return "\(scopeReview) \(lead)" }
        return lead
    }

    /// A test run. `check`: Pebble's own ad hoc check; `checkRun`: the project's tests and the check, each apart.
    public static func leadTests(check: Bool, checkRun: Bool) -> String {
        if check && checkRun {
            return
                "Runs the project's tests, then Pebble's own check alone, each in a temporary copy. Your project files don't change."
        }
        return check
            ? "Runs Pebble's own check, added to a temporary copy for this run only. Your project files don't change."
            : "Runs the project's tests in a temporary copy. Your project files don't change."
    }

    public static func leadCommand(writable: Bool) -> String {
        writable
            ? "Runs this command in your project, where it can change files. Pebble can't undo a command."
            : "Runs this command in your project without changing files."
    }

    public static let leadPlugin =
        "Calls a tool of a connector you turned on. What it changes depends on that service; Pebble can't undo it."

    public static func leadGit(undo: Bool) -> String {
        undo
            ? "Undoes an earlier Git change."
            : "Runs this Git change in your project. You can propose an undo afterwards, as a new reviewed plan."
    }

    public static func leadWorktree(retire: Bool) -> String {
        retire
            ? "Removes an agent's separate working copy of the project."
            : "Creates a separate working copy of your project for an agent. Your project stays as it is."
    }

    public static let leadInstall =
        "Installs the project's locked dependencies into a folder Pebble manages, outside your project."

    /// Opening an app on the Mac, optionally with a document and in the background.
    public static func leadApp(document: String? = nil, background: Bool) -> String {
        if let document, !document.isEmpty {
            return
                "Opens \(document) in this app on your Mac\(background ? ", without bringing it to the front" : ""). Pebble won't control what happens inside it."
        }
        return background
            ? "Opens this app in the background on your Mac, without bringing it to the front. Pebble won't control what happens inside it."
            : "Opens this app on your Mac. Pebble won't control what happens inside it."
    }

    public static let leadShell = "Runs this command in Pebble's sandbox on your Mac."
    public static let leadFile = "Writes this file on your Mac. Pebble keeps a copy first, so you can undo it."

    /// A press or typing in a window the person shared. `sending`: the press looks like sending, submitting, saving,
    /// deleting or buying (Pebble's F166 reasons).
    public static func leadScreen(sending: Bool, typing: Bool) -> String {
        if sending {
            return
                "Does this in the app window you shared. It may send, submit, save, delete or buy, and Pebble can't undo it."
        }
        return typing
            ? "Types this in the app window you shared. Pebble can't undo typing."
            : "Presses this in the app window you shared. Pebble can't undo a press."
    }

    /// Letting Pebble see and use one window.
    public static func leadScreenGrant(filePanel: Bool, screenshots: Bool, fullAccess: Bool) -> String {
        if filePanel {
            return
                "This window is a file panel: it shows one of your folders, and Pebble would read the names of the files listed there. Allow it only if that is what you want."
        }
        var text = "Lets Pebble see and use this one window in this conversation, for up to 15 minutes"
        text += screenshots ? ", with pictures of it when needed. " : ". "
        text +=
            fullAccess
            ? "In Full access Pebble runs the presses your messages ask for; anything that may spend money still asks."
            : "Most presses still ask you first."
        if screenshots {
            text += " If macOS asks whether Pebble may bypass its window picker, choose Allow for the pictures."
        }
        return text
    }

    public static let leadURL =
        "Opens this address in your browser. Pebble can't see the page, so it can't confirm what happens there."
    public static let leadScreenRaise =
        "Brings this window to the front so Pebble can read it. macOS may switch to its desktop."
    public static let leadAppAction =
        "Asks this app to do one thing through its own scripting. Pebble never sends mail or deletes anything this way."

    /// Sites in the person's browser. `window`: Pebble opens a new window of that browser (D128).
    public static func leadBrowserGrant(window: Bool, browserName: String? = nil) -> String {
        window
            ? "Opens these sites in a new \(browserName ?? "browser") window that Pebble reads and uses in this conversation, for up to 15 minutes. Sending, buying or deleting still asks you."
            : "Lets Pebble use these sites in its own tab in your browser in this conversation, for up to 15 minutes. Sending, buying or deleting still asks you."
    }

    // MARK: Headings: the exact thing, when it is not a command or a path (App.vue's card headings)

    public static func headingTests(check: Bool) -> String { check ? "Run an ad hoc check" : "Run isolated tests" }
    public static func headingGit(operation: String) -> String { "Git \(operation)" }
    public static func headingWorktree(retire: Bool) -> String {
        retire ? "Retire child worktree" : "Allocate child worktree"
    }
    public static func headingInstall(kind: String) -> String { "Install dependencies (\(kind))" }
    public static func headingPlugin(name: String, tool: String) -> String { "\(name) / \(tool)" }
    public static func headingUse(_ app: String) -> String { "Use \(app)" }
    public static func headingOpen(_ thing: String) -> String { "Open \(thing)" }
    public static func headingOpen(document: String, in app: String) -> String { "Open \(document) in \(app)" }
    public static func headingBringForward(_ app: String) -> String { "Bring \(app) forward" }
}

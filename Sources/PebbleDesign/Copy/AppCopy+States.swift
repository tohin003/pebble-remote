import Foundation
import PebbleProtocol

// Lane W (UX audit 2026-10-30, docs/reviews/ux-audit-2026-10-30.md fixes 4, 6, 9 and the small ones): the phone's words
// where Pebble's window shows a tool name, a field name or a raw state ("AppAction (app_action)", "Basis: after
// present", "Command: unknown"). Pebble's own words stay in RecoveryCopy, StatusCopy and ModeCopy, checked against
// Pebble's files; these are the phone's variants beside them (docs/DESIGN.md §4).
extension AppCopy {
    // MARK: - Uncertain outcomes: each step in words (U-29)

    /// A step Pebble lost track of, named the way Pebble's activity list names it. Pebble's readback is content-free
    /// (no file, no arguments), so the words are Pebble's own line for the tool without its file or app (app.py
    /// `tool_label`), plus the app's name where the task's paused window says which app the step acted in.
    nonisolated public enum Steps {
        /// A step's name: Pebble's words for its tool, else words for its kind, else a plain fallback. Never the raw
        /// tool or kind name. `app` is the app whose window the step acted in, when the task paused exactly one.
        public static func name(tool: String?, kind: String?, app: String? = nil) -> String {
            if let tool = tool.flatMap({ $0.isEmpty ? nil : $0 }) {
                if let app = app.flatMap({ $0.isEmpty ? nil : $0 }), let words = inAppWindow(tool, app: app) {
                    return words
                }
                if let words = toolWords[tool] { return words }
            }
            if let kind = kind.flatMap({ $0.isEmpty ? nil : $0 }), let words = kindWords[kind] { return words }
            return fallback
        }

        /// The name for a tool or kind this app has no words for.
        public static let fallback = "A step Pebble took"

        /// The three steps that act in one app window, with the app's name ("Acting in Mail's window").
        static func inAppWindow(_ tool: String, app: String) -> String? {
            switch tool {
            case "ScreenAct": "Acting in \(app)\u{2019}s window"
            case "ScreenObserve": "Looking at \(app)\u{2019}s window"
            case "ScreenRequest": "Asking to use \(app)\u{2019}s window"
            default: nil
            }
        }

        /// Pebble's activity words for each of its tools (app.py `tool_label`, without the file or app it names), and
        /// plain words for the tools Pebble's window leaves as their names. Every tool in Pebble's tool classes is here
        /// (StateWordsTests checks it).
        public static let toolWords: [String: String] = [
            // Reading
            "Read": "Reading a file",
            "ReadAttachment": "Reading an attachment",
            "ReadURL": "Reading a public web source",
            "ReadSource": "Reading a recorded source",
            "ReadProcess": "Reading command output",
            "ReadRunEvidence": "Reading what the task recorded",
            "LoadSkill": "Loading skill guidance",
            "LoadPluginTool": "Loading a plugin tool",
            "LoadPluginData": "Loading plugin data",
            "ReadPluginData": "Reading plugin data",
            "ReadPluginMedia": "Reading plugin media",
            "ReadGitStatus": "Reading Git status",
            "ReadGitDiff": "Reading Git changes",
            "ReadGitHistory": "Reading Git history",
            "ReadGitPlanReceipt": "Reading back a Git plan",
            "ReadGitWorktrees": "Reading Git worktrees",
            "ReadWorktreeExport": "Reading a worktree export",
            "ListProjectRecipes": "Finding project test and build recipes",
            "ScreenObserve": "Looking at the app window",
            "ResearchStatus": "Checking research progress",
            "ReadFile": "Reading a file",
            "Screenshot": "Taking a screenshot",
            // Searching
            "Glob": "Finding project files",
            "Grep": "Searching project source",
            "SearchFiles": "Finding relevant source",
            "CodeReferences": "Following Python definitions and references",
            "WebSearch": "Searching the web",
            "Weather": "Looking up current weather",
            "SearchPluginTools": "Finding reviewed plugin tools",
            "SearchPluginData": "Searching plugin data",
            "ResearchPlan": "Planning research",
            "FindTool": "Finding a tool for the task",
            // Editing
            "Write": "Drafting a file",
            "Append": "Extending a file",
            "Edit": "Preparing an edit",
            "ProposePatch": "Proposing a change",
            "IntegrateAgentPatch": "Adding an agent\u{2019}s change",
            "ProposeGitChange": "Preparing a reviewed Git plan",
            "PreviewWorktreeExport": "Previewing a worktree export",
            "IntegrateWorktreeFile": "Adding a file from a worktree",
            "WriteFile": "Writing a file",
            "EditFile": "Editing a file",
            // Testing
            "RunTests": "Requesting isolated tests",
            "RunRecipe": "Requesting an isolated project recipe",
            // Running
            "RunCommand": "Reviewing terminal command",
            "StartCommand": "Starting a background command",
            "WaitProcess": "Waiting for command output",
            "StopProcess": "Stopping a command",
            "WriteProcessInput": "Typing into a command",
            "RunPlan": "Proposing a command plan",
            "StartPreview": "Starting a local static preview",
            "PrepareEnvironment": "Preparing a dependency install for review",
            "RunCode": "Running a script",
            "Shell": "Running a command in the sandbox",
            // Agents
            "SpawnAgent": "Starting an agent",
            "SpawnWorktreeAgent": "Starting an agent in a worktree",
            "ReadAgentTree": "Checking on agents",
            "SendAgentMessage": "Messaging an agent",
            "WaitForAgents": "Waiting for agents",
            "DelegateAgentTask": "Handing a task to an agent",
            "StopAgent": "Stopping an agent",
            "RetryAgent": "Trying an agent again",
            "AskParentQuestion": "Asking a question",
            "AnswerAgentQuestion": "Answering an agent\u{2019}s question",
            "PromoteAgentQuestion": "Passing an agent\u{2019}s question to you",
            "ReviewAgentResult": "Reviewing an agent\u{2019}s result",
            "ReadAgentMessage": "Reading an agent\u{2019}s message",
            "ReadAgentPatch": "Reading an agent\u{2019}s change",
            "RequestAgentEffect": "Asking to make an agent\u{2019}s change",
            "ReadAgentEffect": "Reading an agent\u{2019}s change request",
            "ReadAgentEffects": "Reading agents\u{2019} change requests",
            "ExecuteAgentEffect": "Making an agent\u{2019}s change",
            "DismissAgentEffect": "Dismissing an agent\u{2019}s change request",
            // Views
            "UIRender": "Drawing an interactive view",
            "UIUpdate": "Updating an interactive view",
            "RenderMod": "Drawing a view",
            // Thinking
            "AskUserQuestion": "Asking you a question",
            "UpdatePlan": "Updating the task plan",
            "UpdateGoal": "Updating goal progress",
            "MemoryPropose": "Proposing a memory to save",
            // Apps, sites and connectors
            "OpenApp": "Preparing to open an app",
            "PluginCall": "Calling a plugin",
            "FetchPluginData": "Fetching plugin data",
            "ScreenAct": "Acting in the app window",
            "ScreenRequest": "Asking to use an app window",
            "OpenURL": "Opening a web page",
            "AppAction": "Asking an app to do one thing",
            "BrowserRequest": "Asking to use websites in your browser",
        ]

        /// The kinds of action Pebble records (reconcile.py's action kinds, and a few older names), for a step whose
        /// tool Pebble didn't record.
        public static let kindWords: [String: String] = [
            "edit": "A change to a file",
            "file": "A change to a file",
            "git": "A Git change",
            "command": "A command",
            "tests": "A test run",
            "install": "An install",
            "plugin": "A plugin call",
            "screen": "A step in an app window",
            "app_action": "An action in an app",
            "app": "An action in an app",
            "url": "Opening a web page",
        ]

        /// VoiceOver for "Settle from Readback" on one step.
        public static func settleLabel(_ name: String) -> String {
            "Settle \u{201C}\(name)\u{201D} from Pebble\u{2019}s readback"
        }

        /// VoiceOver for the note field of one step.
        public static func whatYouChecked(_ name: String) -> String { "What you checked for \u{201C}\(name)\u{201D}" }

        /// What Pebble's readback rests on ("Basis: after present" in Pebble's window), in words; nil where the verdict
        /// already says it, or for a basis this app has no words for (the verdict line stands alone then).
        public static func basis(_ code: String) -> String? {
            switch code {
            case "after_present": "Pebble found the change in place."
            case "before_present": "Pebble found things as they were before."
            case "absent_on_create": "What this step would have made isn\u{2019}t there."
            case "never_performed": "This step never ran."
            case "no_receipt", "no_effect_started", "no_admission_record", "refused_before_start", "no_spawn_record",
                "no_registration":
                "Pebble\u{2019}s records show it never started."
            case "folder_absent": "The folder it would have made isn\u{2019}t there."
            case "exit_receipt", "exit_observed": "Pebble saw the command end."
            case "still_running": "It\u{2019}s still running."
            case "no_broker_action": "Pebble kept nothing it can check for this step."
            case "not_observable": "Pebble can no longer see that window or tab."
            case "not_provable_by_reobservation": "Looking at the window again can\u{2019}t show whether it worked."
            case "indistinguishable": "Before and after look the same, so Pebble can\u{2019}t tell."
            case "readback_limit": "Pebble checks only the first 64 steps at a time."
            case "root_unavailable", "root_replaced": "The project folder isn\u{2019}t there to check."
            case "absent_by_fields": "Pebble found no match, which doesn\u{2019}t prove it didn\u{2019}t happen."
            case "ambiguous_match": "Several things match, so Pebble can\u{2019}t tell which one this step made."
            default: nil
            }
        }
    }

    // MARK: - A command's state in words (U-33, U-32, U-44)

    /// A command Pebble started, by its state ("Command: running" in Pebble's window). Pebble sends no command text
    /// with it, so the sentence says what the command is doing, not which command it is.
    nonisolated public enum CommandState {
        public static func title(_ state: String) -> String {
            switch state {
            case "admitted": "A command is starting"
            case "running": "A command is running"
            case "succeeded": "A command finished"
            case "failed": "A command ended with an error"
            case "stopped": "A command was stopped"
            case "limited": "A command reached its limit"
            case "refused": "A command didn\u{2019}t run"
            case "unknown": "Pebble lost track of a command"
            default: "A command"
            }
        }

        /// Pebble's "The service did not observe this outcome. Inspect external effects before retrying. This run
        /// still requires verification.", in plain words.
        public static let lostTrack = "Pebble couldn\u{2019}t see how this command ended. Check what it did before you run it again."

        /// "Type into the command": the command's latest lines, so the person sees what it asks.
        public static let latestLines = "What the Command Shows"
        /// After a line or a key went to the command.
        public static let sent = "Sent."
        /// Pebble's "Send line" in the sheet's bar, short so the title fits beside it (UX audit U-51); VoiceOver and the
        /// button's identifier keep Pebble's "Send Line".
        public static let send = "Send"
        /// The menu beside the field that holds Pebble's "Send Ctrl-C" and "Send Ctrl-D".
        public static let keys = "Send a Key"
        /// "Record my inspection" with no note yet: Pebble records an inspection only with a note.
        public static let noteNeeded = "Write what you checked to record it."
    }

    // MARK: - How Pebble acts, short (U-07, U-38)

    /// One line per mode on the phone; Pebble's full copy (ModeCopy, word for word) is one tap away.
    nonisolated public enum Modes {
        public static func summary(_ mode: PermissionMode) -> String {
            switch mode {
            case .ask: "Asks before anything that changes your project or your Mac."
            case .auto: "Works in this project on its own and asks before riskier steps."
            case .full: "Runs each step your messages ask for. Spending money always asks."
            }
        }

        /// The disclosure with Pebble's full copy for every mode.
        public static let whatEachModeAllows = "What Each Mode Allows"

        /// Before Full access: the confirmation's title, its button (destructive: it widens what Pebble may do) and two
        /// sentences of Pebble's (UX audit U-50). Pebble's Mac asks nothing first; its Settings show the whole warning
        /// while Full access is on, as the phone does, and what the mode allows is under "What Each Mode Allows".
        public static let fullAccessTitle = "Use Full Access?"
        public static let fullAccessConfirm = "Use Full Access"
        /// What Pebble does in the mode: the second sentence of the warning Pebble's Settings show while Full access is on
        /// (AdvancedSettings.vue), up to its semicolon. 2.0.0's "What's new" dropped 1.9.14's sentence used before.
        public static let fullAccessSummaryPebble =
            "Pebble checks each step that would ask against your own messages and runs only what they ask for, never spending money."
        /// The first sentence of that warning.
        public static let fullAccessRiskPebble = "Full access increases the impact of mistakes and prompt injection."
        public static var fullAccessMessage: String { fullAccessSummaryPebble + " " + fullAccessRiskPebble }

        /// Once per section, where every switch in it asks for Face ID (instead of a glyph on each row).
        public static let changesAskForFaceID = "Changes here ask for Face ID."
    }

    // MARK: - Continuing on another model: the decision first (U-34)

    nonisolated public enum HandoffDecision {
        /// The one sentence that says what approving and starting does. `model` is the model the person chose.
        public static func question(model: String?, messages: Int?, onMac: Bool) -> String {
            let name = model.flatMap { $0.isEmpty ? nil : $0 } ?? theModelYouChose
            guard let messages else { return "Continue this conversation on \(name) as a new run?" }
            if messages == 0 { return "Continue this conversation on \(name) as a new run? No message is sent." }
            let count = messages == 1 ? "1 message" : "\(messages) messages"
            return onMac
                ? "Continue this conversation on \(name), on your Mac? Pebble sends it \(count) and starts a new run there."
                : "Continue this conversation on \(name)? Pebble uploads \(count) and starts a new run there."
        }

        /// Pebble's words for the destination when the phone doesn't know its name (ModelHandoff.vue's intro).
        public static let theModelYouChose = "the model you chose"
        /// The disclosure over Pebble's plan: route, fingerprint, the messages by role, what is withheld.
        public static let details = "Details"
    }

    // MARK: - Sheet buttons short enough for the title (U-27, U-47)

    /// A sheet's confirm button, short so the sheet's title isn't cut. VoiceOver keeps Pebble's whole words
    /// (`TerminalCommand.review`, `WebSource.attach`).
    nonisolated public enum SheetActions {
        public static let review = "Review"
        public static let attach = "Attach"
    }

    // MARK: - Apps and sites by name (U-28, U-40)

    nonisolated public enum Places {
        /// An app's name from its bundle ID, as macOS shows it ("com.apple.mail" is "Mail", "com.apple.iCal" is
        /// "Calendar"). Pebble's window takes the ID's last part as it is ("mail"); the phone keeps an app's capitals.
        public static func appName(bundleID: String?) -> String? {
            guard let bundleID = bundleID?.trimmingCharacters(in: .whitespaces), !bundleID.isEmpty else { return nil }
            if let known = knownApps[bundleID.lowercased()] { return known }
            guard let last = bundleID.split(separator: ".").last.map(String.init), !last.isEmpty else { return nil }
            // A last part in lower case only ("calculator") takes a capital; one with its own capitals stays.
            return last == last.lowercased() ? last.prefix(1).uppercased() + last.dropFirst() : last
        }

        /// Apps whose name isn't their bundle ID's last part with a capital.
        static let knownApps: [String: String] = [
            "com.apple.ical": "Calendar",
            "com.apple.mobilesms": "Messages",
            "com.apple.addressbook": "Contacts",
            "com.apple.systempreferences": "System Settings",
            "com.apple.textedit": "TextEdit",
            "com.apple.facetime": "FaceTime",
            "com.apple.appstore": "App Store",
            "com.apple.activitymonitor": "Activity Monitor",
            "com.apple.quicktimeplayerx": "QuickTime Player",
            "com.apple.voicememos": "Voice Memos",
            "com.apple.image_capture": "Image Capture",
            "com.apple.screensharing": "Screen Sharing",
            "com.apple.iwork.pages": "Pages",
            "com.apple.iwork.numbers": "Numbers",
            "com.apple.iwork.keynote": "Keynote",
            "com.apple.dt.xcode": "Xcode",
            "com.apple.tv": "TV",
            "com.google.chrome": "Google Chrome",
            "com.microsoft.vscode": "Visual Studio Code",
            "com.tinyspeck.slackmacgap": "Slack",
            "ai.perplexity.comet": "Comet",
            "com.openai.chat": "ChatGPT",
            "com.apple.findmy": "Find My",
            "com.apple.ibooksx": "Books",
            "com.apple.photobooth": "Photo Booth",
            "com.apple.fontbook": "Font Book",
            "com.apple.diskutility": "Disk Utility",
            "com.apple.keychainaccess": "Keychain Access",
            "com.apple.scripteditor2": "Script Editor",
            "com.spotify.client": "Spotify",
            "us.zoom.xos": "zoom.us",
            "com.microsoft.word": "Microsoft Word",
            "com.microsoft.excel": "Microsoft Excel",
            "com.microsoft.powerpoint": "Microsoft PowerPoint",
            "com.microsoft.outlook": "Microsoft Outlook",
        ]

        /// A site by its name: "https://docs.github.com" is "docs.github.com" (no scheme, no "www."; a port stays).
        /// Anything that isn't an address is shown as Pebble sent it.
        public static func site(_ origin: String) -> String {
            guard let url = URL(string: origin), url.scheme != nil, let host = url.host(), !host.isEmpty else {
                return origin
            }
            let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return url.port.map { "\(name):\($0)" } ?? name
        }

        /// A tab's sites: the first by name, and how many more.
        public static func sites(_ origins: [String]) -> String? {
            guard let first = origins.first else { return nil }
            return origins.count == 1 ? site(first) : "\(site(first)) and \(origins.count - 1) more"
        }

        /// Which browser a shared tab is in (Pebble's "Your Chrome tab"; Pebble's own tab without its retired name).
        public static let chromeTab = "Your Chrome tab"
        public static let pebbleTab = "A tab in Pebble"
        public static let appWindow = "An app window"
    }

    // MARK: - A held task's word (U-20)

    nonisolated public enum Held {
        /// Pebble's companion words for a task held for verification (PetRunSummary.vue: "needs verification"), in
        /// place of the `blocked` key's "Blocked", which reads like an error.
        public static let needsVerification = "Needs verification"
        /// VoiceOver: Pebble's sentence for the state (RunPanel.vue).
        public static let label = "Pebble\u{2019}s change isn\u{2019}t verified yet"
    }

    // MARK: - File paths, spoken (accessibility)

    nonisolated public enum Paths {
        /// A path as VoiceOver says it: "src/settings/ThemeToggle.tsx" is "ThemeToggle.tsx in src/settings". Not a
        /// path (no slash, any space or line break, or a web address): nil, and the text is read as it is.
        public static func spoken(_ text: String) -> String? {
            let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.contains("/"), path.rangeOfCharacter(from: .whitespacesAndNewlines) == nil, !path.contains("://")
            else { return nil }
            var parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let file = parts.popLast() else { return nil }
            if parts.isEmpty { return file }
            return "\(file) in \(path.hasPrefix("/") ? "/" : "")\(parts.joined(separator: "/"))"
        }
    }

    // MARK: - Settings, as Pebble's Settings on the Mac (fix 7: U-35, U-36, U-37, U-39)

    /// The Settings tab (once "Control"): Pebble's Settings sections in its sidebar's order and words, the iPhone one in
    /// the Mac's place (docs/parity/IA.md rule 2; the lead's decision, 23:03).
    nonisolated public enum SettingsTab {
        /// Pebble's Settings sidebar, word for word (AdvancedSettings.vue `TAB_LABELS`), in its order. The Mac lists
        /// Views only while Developer features is on, a switch its window keeps to itself, so the phone leaves Views out.
        public static let models = "Models"
        public static let permissions = "Permissions"
        public static let memory = "Memory"
        public static let skills = "Skills & connectors"
        public static let views = "Views"
        public static let storage = "Data & storage"
        public static let privacy = "Privacy & Stealth"
        public static let iPhone = "iPhone"
        public static let appearance = "Appearance"
        public static let general = "General"
        public static let order = [
            models, permissions, memory, skills, views, storage, privacy, iPhone, appearance, general,
        ]

        /// What only Pebble on the Mac can do shows as a grey row with this note, and why under the section (IA rule
        /// 6), never as a dead button.
        public static let onYourMac = "On your Mac"
        public static let connectModel = "Connect a Model"
        public static let connectModelNote =
            "Signing in, connecting a provider and adding a model file happen in Pebble\u{2019}s Settings on your Mac."
        public static let skillsAndConnectors = "Skills and Connectors"
        public static let skillsNote =
            "Adding, reviewing and turning skills and connectors on or off happen in Pebble\u{2019}s Settings on your Mac."

        /// iPhone: the Mac's rows for this app (RemoteSettings.vue) the phone can show, and the phone's own. The Mac's
        /// "After Face ID, your iPhone can act for"; on the phone only the place changes.
        public static let unlockForPebble = "After Face ID, your iPhone can act for"
        public static let unlockFor = "After Face ID, this iPhone can act for"
        /// Pebble's choices' words: "1 hour" for 60 minutes, else "{n} minutes" ("1 minute" for one).
        public static func unlockTime(minutes: Int) -> String {
            minutes == 60 ? "1 hour" : minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        /// The Mac's list of what the phone did (its heading, word for word); the bridge doesn't send it.
        public static let whatYourIPhoneDid = "What your iPhone did"
        public static let iPhoneNote =
            "Pebble\u{2019}s Settings \u{203A} iPhone on your Mac pairs a new iPhone, sets how long Face ID unlocks it and lists what it did."
        public static let storageRow = "Pebble\u{2019}s Folder and Space Used"
        public static let storageNote =
            "Pebble\u{2019}s folder, its readable copies in Documents and the space it uses are in Pebble\u{2019}s Settings on your Mac."
        /// A shortcut that names where it leads (IA rule 4): Recently Deleted is on the Chats tab.
        public static let inChats = "In Chats"

        /// The phone's lists across every conversation, which Pebble's Mac shows per conversation (Details › Tools),
        /// until each conversation's Details has them.
        public static let acrossConversations = "Across Conversations"
        public static let acrossConversationsNote =
            "On your Mac, each conversation\u{2019}s Details \u{203A} Tools shows its schedules and shared windows."

        /// Pebble's General › About: the version of Pebble on the Mac.
        public static let aboutPebble = "About Pebble"

        /// "Notifications" in Pebble's General settings are the Mac's (U-39); the phone says so, as "Appearance on
        /// Your Mac" does.
        public static let notificationsOnYourMac = "Notifications on Your Mac"
    }

    /// Where a model runs, as its row's second line (U-37). Pebble names a model file on the Mac "On this device", the
    /// Mac itself; on the phone that reads as the iPhone, so only the place changes (docs/DESIGN.md §4).
    nonisolated public enum ModelPlace {
        /// Pebble's words (providers.py: a GGUF model's `provider_name`).
        public static let onThisDevicePebble = "On this device"
        /// The phone's variant.
        public static let onYourMac = "On your Mac"

        public static func provider(_ name: String?) -> String? {
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return name.caseInsensitiveCompare(onThisDevicePebble) == .orderedSame ? onYourMac : name
        }
    }
}

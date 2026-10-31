import Foundation
import PebbleProtocol

/// Every string the screens show that is not one of Pebble's own tables (`StatusCopy`, `ModeCopy`, `ReviewCopy`,
/// `RunCopy`). Written in Pebble's voice:
///
/// - plain words that say what Pebble or the app actually does; no internal words (`BannedWords`);
/// - honest: only what Pebble reports, and never a promise the app can't keep (after a timeout the app says it can't
///   tell whether something happened, not that nothing changed);
/// - the person decides: buttons name the action, and every step that can't be undone says so;
/// - Apple's capitalization: title style for tab and screen titles, section headers, buttons and alert titles;
///   sentence style for sentences. Pebble's own fixed phrases ("Needs your review", "Ask for approval") stay exactly
///   as Pebble writes them.
///
/// Names are stable once posted (the screens use them); new strings are added, never renamed. Need a string that isn't
/// here? Ask lane D on docs/TEAM_BOARD.md; don't write it in a screen.
nonisolated public enum AppCopy {
    public static let appName = "Pebble Remote"
    public static let pebble = "Pebble"

    // MARK: - Shared

    nonisolated public enum Tabs {
        public static let pebble = "Pebble"
        public static let chats = "Chats"
        public static let reviews = "Reviews"
        /// The fourth tab: Pebble's Settings, then This iPhone (docs/parity/IA.md rule 2; once "Control", U-35).
        public static let control = "Settings"

        /// A tab's name.
        public static func name(_ tab: PebbleSymbol.Tab) -> String {
            switch tab {
            case .pebble: pebble
            case .chats: chats
            case .reviews: reviews
            case .control: control
            }
        }
    }

    nonisolated public enum Common {
        public static let cancel = "Cancel"
        public static let done = "Done"
        public static let save = "Save"
        public static let ok = "OK"
        public static let close = "Close"
        public static let more = "More"
        public static let retry = "Try Again"
        public static let openSettings = "Open Settings"
    }

    // MARK: - The Pebble tab

    nonisolated public enum Home {
        public static let title = "Pebble"
        /// Under the avatar when nothing runs.
        public static let idle = "Not working on anything right now"
        public static let idleDetail = "Ask Pebble something and you'll see it work here."
        public static let workingNow = "Working Now"
        /// Pebble's own phrase, as a section header.
        public static let needsYourReview = "Needs your review"
        public static func waitingCount(_ count: Int) -> String {
            count == 1 ? "1 item is waiting for you" : "\(count) items are waiting for you"
        }
        public static let seeAll = "See All"
        public static let openReviews = "Open Reviews"
        public static let askPebble = "Ask Pebble"
        public static let askPebbleHint = "Starts a new conversation with Pebble on your Mac"
        /// The quick field's button: it sends the words as the first message of a new conversation in Companion.
        public static let startConversation = "Start a New Conversation"
        public static let askPlaceholder = "What should Pebble do?"
        public static let askFooter = "Starts a new conversation in Pebble's default project."
        /// The mode section: Pebble's own label ("HOW PEBBLE ACTS").
        public static let mode = "How Pebble Acts"
        public static let yourMac = "Your Mac"
        public static let pebbleNotOpen = "Pebble isn't open on your Mac"
        public static let pebbleNotOpenDetail = "Open Pebble on your Mac and it shows up here."
        public static let demoBanner = "This is the demo. Nothing reaches your Mac."
        public static func pebbleVersion(_ version: String) -> String { "Pebble \(version)" }
    }

    // MARK: - Your Mac (Pebble tab and Control)

    nonisolated public enum Mac {
        public static let title = "Your Mac"
        public static let battery = "Battery"
        public static func batteryPercent(_ percent: Int) -> String { "\(percent)%" }
        public static let onPower = "On power"
        public static let onBattery = "On battery"
        public static let charging = "Charging"
        /// "82%, charging"; "82%, on battery"; "On power" for a Mac without a battery.
        public static func batteryLine(percent: Int?, charging: Bool?, onPower: Bool?) -> String {
            guard let percent else { return onPower == false ? onBattery : self.onPower }
            if charging == true { return "\(percent)%, charging" }
            if onPower == true { return "\(percent)%, on power" }
            return "\(percent)%, on battery"
        }
        public static let keepAwake = "Keep Awake"
        public static let keepAwakeOnNote = "Your Mac won't go to sleep, so Pebble can keep working."
        public static let keepAwakeOffNote = "Your Mac sleeps as usual. Pebble stops working while it sleeps."
        public static let keepAwakeBatteryNote =
            "On battery, keeping your Mac awake uses its charge faster, so Pebble Remote asks for Face ID to turn it on."
    }

    // MARK: - Chats

    nonisolated public enum Chats {
        public static let title = "Chats"
        public static let searchPrompt = "Search conversations"
        /// Every entry point that starts a conversation, in Pebble's words (the sidebar's first button, ⌘N).
        public static let newConversation = "New conversation"
        /// Pebble's own name for a conversation without a title.
        public static let untitled = "New conversation"
        public static let noProject = "No project"
        public static let rename = "Rename"
        public static let renameTitle = "Rename Conversation"
        public static let renameField = "Title"
        public static let cancel = "Cancel"
        public static let save = "Save"
        public static func waiting(_ count: Int) -> String { "\(count) waiting" }
        public static func project(_ name: String) -> String { "In \(name)" }
        public static let emptyTitle = "No Conversations Yet"
        public static let emptyDetail = "Ask Pebble something, here or on your Mac, and the conversation shows up here."
        /// A conversation's row while words written on this iPhone wait unsent, before their first line (as a
        /// messaging app marks a chat's draft).
        public static let draft = "Draft:"
    }

    // MARK: - A conversation

    nonisolated public enum Conversation {
        public static let you = "You"
        public static let pebble = "Pebble"
        public static let placeholder = "Message Pebble"
        /// While a run works, a message reaches it as guidance.
        public static let placeholderWhileWorking = "Tell Pebble while it works"
        public static let send = "Send"
        public static let sendHintWhileWorking = "Pebble reads it while it works"
        public static let stop = "Stop"
        public static let stopHint = "Stops this task. Steps that already ran aren't undone."
        public static let pause = "Pause"
        public static let resume = "Resume"
        public static let loadEarlier = "Show Earlier Messages"
        public static let loadingEarlier = "Loading earlier messages"
        public static let jumpToLatest = "Jump to Latest"
        /// Opens a run's conversation (also VoiceOver's named action on the bottom accessory's run bar).
        public static let open = "Open Conversation"
        public static let stillWriting = "Pebble is still writing"
        public static let copy = "Copy"
        public static let copied = "Copied"
        public static let more = "More"
        public static let whatPebbleDid = RunCopy.whatPebbleDid
        public static let emptyTitle = "Ask Pebble Anything"
        public static let emptyDescription =
            "Pebble works on your Mac, in your projects and apps. Ask here and follow along."
        public static let loading = "Loading conversation"
        // How a run ended when Pebble's counts are missing (otherwise use `RunCopy.endLine`)
        public static func finished(_ elapsed: String?) -> String { elapsed.map { "Finished in \($0)" } ?? "Finished" }
        public static let stopped = "Stopped"
        public static let interrupted = "Interrupted"
        public static let paused = "Paused"
        public static func problem(_ note: String?) -> String { note.map { "Hit a problem: \($0)" } ?? "Hit a problem" }
        /// VoiceOver value for an elapsed time ("2 min 05 s"; "about 2 min" when the phone counted it).
        public static func elapsedAccessibility(_ text: String, exact: Bool) -> String { exact ? text : "about \(text)" }
    }

    // MARK: - Your space: the Chats tab as Pebble's sidebar (App.vue, the window's sidebar)

    nonisolated public enum Sidebar {
        /// Pebble's sidebar headings ("YOUR SPACE", "RECENT CONVERSATIONS"), as section headers.
        public static let yourSpace = "Your Space"
        public static let recentConversations = "Recent Conversations"
        /// Pebble's name for conversations without a project.
        public static let companion = "Companion"
        public static let connectProject = "Connect a project"
        /// What a place's row does (App.vue's title on each project row): it starts a new conversation there.
        public static func newConversation(in place: String) -> String { "New conversation in \(place)" }
        public static let newConversationHint = "Nothing reaches your Mac until you send the first message."
        public static let connectProjectHint = "Choose a folder on your Mac for a new conversation."
        public static let noConversations = "Conversations you start here or on your Mac show up here."
    }

    // MARK: - A new conversation, before its first message (a draft)

    nonisolated public enum Draft {
        public static let title = Chats.newConversation
        /// Pebble's welcome in an empty conversation (App.vue), word for word.
        public static let welcome = "Good to see you."
        public static let welcomeInProject = "Let\u{2019}s build something."
        public static let companionDescription =
            "A small companion for your next big idea.\nThink through a problem, write code, or get things moving."
        public static func projectDescription(_ project: String) -> String {
            "I'm here to help you explore, fix, and build in \(project)."
        }
        /// The where control: the place the conversation starts in.
        public static func startsIn(_ place: String) -> String { "In \(place)" }
        public static let whereLabel = "Where"
        public static let whereHint = "Choose where this conversation starts."
        /// Under the where control: a folder no conversation uses yet asks for Face ID at the first message.
        public static let newFolderNote =
            "Pebble connects this folder when you send the first message, after Face ID. Source reads stay inside this folder."
    }

    // MARK: - Where a conversation is (its navigation title's menu)

    nonisolated public enum Place {
        /// VoiceOver's name for the title menu.
        public static let menu = "Where This Conversation Is"
        public static let menuHint = "Start a new conversation here, or connect a project."
        /// The open conversation's place keeps a conversation with messages where it is: picking a project starts a
        /// new one there (App.vue `openProject`, `chooseProject`).
        public static let startsNewConversation =
            "This conversation keeps its messages where they are. The project you choose starts a new conversation, as in Pebble on your Mac."
    }

    // MARK: - The composer's "+" menu (App.vue "Add context"), in Pebble's order and words

    nonisolated public enum AddContext {
        /// The "+" button's name in Pebble's window (its title and VoiceOver label).
        public static let title = "Add context"
        public static let terminalCommand = "Terminal command"
        public static let attachFile = "Attach a file"
        public static let readWebSource = "Read a web source"
        public static let connectProject = Sidebar.connectProject
        /// Where a file comes from on the iPhone.
        public static let photoLibrary = "Photo Library"
        public static let files = "Files"
        public static let unreadableFile = "Pebble Remote couldn't read that file. Try another one."
        /// While a task runs, attachments wait: Pebble takes them only with a new task.
        public static let whileWorkingHint = "Available when Pebble finishes the current task."
    }

    /// The composer's "Terminal command": Pebble's dialog, word for word.
    nonisolated public enum TerminalCommand {
        public static let title = "Run a terminal command"
        public static func intro(_ project: String?) -> String {
            "Run one command in \(project ?? "a connected project"). Review the exact command and access before execution."
        }
        public static let field = AddContext.terminalCommand
        public static let placeholder = "For example: git status --short"
        public static let network = "Request network access for this command"
        public static let note =
            "Pipes, redirections, privileged commands and credential access are blocked. Commands run for up to 60 seconds inside a macOS sandbox, and the output appears in the conversation."
        public static let review = "Review command"
        /// Pebble's words when the conversation has no project.
        public static let needsProject = "Choose a project folder for this conversation first."
        /// Pebble's words while a task runs.
        public static let whileWorking = "Wait for the current task before starting a terminal command."
    }

    /// The composer's "Read a web source": Pebble's dialog, word for word.
    nonisolated public enum WebSource {
        public static let title = "Read a web page"
        public static let intro = "Read a public HTTPS page as source material. Its content gets no tool permissions."
        public static let field = "Public HTTPS source URL"
        public static let placeholder = "https://docs.example.com/guide"
        public static let note = "Text and HTML only. Private networks, redirects, and scripts are blocked."
        public static let attach = "Attach source"
        public static let reading = "Reading\u{2026}"
        /// In a new conversation, nothing is read before the first message.
        public static let readsOnSend = "Pebble reads it when you send the first message."
        /// A web page's chip (App.vue `sourceLabel`): "Read: docs.example.com/guide", the path cut at 24 characters.
        public static func chip(_ address: String) -> String {
            guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme.hasPrefix("http"),
                let host = url.host()
            else { return address }
            let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let path = url.path()
            let shown = path.count > 1 ? String(path.prefix(24)) + (path.count > 24 ? "\u{2026}" : "") : ""
            return "Read: \(site)\(shown)"
        }
    }

    /// "Connect a project": the recent projects, then the Mac's folders (proposal v0.5).
    nonisolated public enum ConnectProject {
        public static let title = Sidebar.connectProject
        public static let recentProjects = "Recent Projects"
        public static let chooseFolder = "Choose a folder on your Mac"
        public static let chooseFolderHint = "Shows the folders in your home folder on your Mac."
        /// A bridge without `remote.folders`.
        public static let onMacOnly = "To connect another folder, use Connect a project in Pebble on your Mac."
        public static let connectThisFolder = "Connect this folder"
        /// Pebble's words for the home folder (policy.py).
        public static let homeRefused = "Choose a project folder rather than your home folder or disk root."
        /// A folder that holds `.git`.
        public static let gitRepository = "Git repository"
        public static let loading = "Loading folders"
        public static let noFoldersTitle = "No Folders Here"
        public static let noFoldersDescription = "This folder has no folders Pebble Remote can show."
        public static let couldNotListTitle = "Can\u{2019}t Show This Folder"
        /// A folder no conversation uses yet.
        public static let newFolderNote =
            "Pebble may read inside a project once it's connected, so a folder no conversation uses yet asks for Face ID."
        /// Pebble's words once a project is connected (App.vue `chooseProject`).
        public static let connected = "Project connected. Source reads stay inside this folder."

        // A new folder on the Mac, made from the phone (proposal v0.6). The Files app's words: a New Folder button, a
        // name field, Cancel and Create.
        /// The toolbar button, and the title of the alert it opens.
        public static let newFolder = "New Folder"
        public static let newFolderHint = "Makes a new folder here, on your Mac. Asks for Face ID."
        /// Under the alert's title: where the folder goes, and that it asks for Face ID.
        public static func newFolderMessage(in parent: String) -> String {
            "Pebble makes it on your Mac, in \(parent). Creating it asks for Face ID."
        }
        public static let folderNamePrompt = "Folder name"
        public static let createFolder = "Create"
        /// Said aloud once the folder exists (VoiceOver).
        public static func folderMade(_ name: String) -> String { "\(name) is made on your Mac." }
        /// Under the folders in the chooser, when the bridge can make folders.
        public static let canMakeFolders = "To make a new folder on your Mac, open a folder and tap New Folder."
    }

    // MARK: - Reviews

    nonisolated public enum Reviews {
        public static let title = "Reviews"
        /// Pebble's own phrase.
        public static let needsYourReview = "Needs your review"
        public static let emptyTitle = "Nothing to Review"
        public static let emptyDescription = "When Pebble needs your approval or an answer, it waits for you here."
        /// Pebble's own word for rejecting a card.
        public static let reject = "Don't Allow"
        /// The approve button for a kind this version doesn't know.
        public static let approveFallback = "Allow"
        public static let approveFooter = "Approving asks for Face ID."
        public static let approveHint = "Asks for Face ID, then Pebble goes ahead"
        public static let rejectHint = "Pebble won't do it"
        public static let working = "Sending your answer"
        public static let openChat = "Open Conversation"
        public static func inConversation(_ title: String) -> String { "In \(title)" }
        public static let showMore = "Show More"
        public static let showLess = "Show Less"
        /// The heading over the exact thing to approve (VoiceOver).
        public static let exactDetail = "Exactly what runs"
        // Questions (Pebble's RunPanel words)
        public static let question = "Pebble asks"
        public static func requestedBy(_ name: String) -> String { "Requested by \(name)" }
        public static let sendAnswer = "Submit Answer"
        public static let yourAnswer = "Your answer"
        public static let otherAnswer = "Write an answer"
        public static let chooseOne = "Choose an answer"
        /// Shown on a required question.
        public static let answerRequired = "Your answer is needed to continue."
        public static let answerRequiredByAgent =
            "This agent needs your answer to continue. Other agents can keep working."
        /// Shown on an optional question.
        public static let answerOptional = "You can answer while other work continues."
        /// `question_cancel` on a required question.
        public static let cancelRequest = "Cancel Request"
        /// `question_cancel` on an optional question.
        public static let skip = "Skip"
        /// Kept for screens written against the first API: it is Pebble's "Skip" (cancelling never means "later").
        public static let notNow = skip

        /// The approve button names what approving does (Pebble's button words, in title style).
        public static func approve(_ kind: CardKind, retire: Bool = false) -> String {
            switch kind {
            case .edit: "Apply Edit"
            case .tests: "Run Tests"
            case .command, .shell: "Run Command"
            case .plugin: "Call Plugin"
            case .git: "Run Git Plan"
            case .worktree: retire ? "Retire Worktree" : "Create Worktree"
            case .install: "Install from Lockfile"
            case .file: "Write File"
            case .screen, .appAction: "Do It"
            case .screenGrant, .browserGrant: "Allow"
            case .url: "Open Link"
            case .screenRaise: "Bring Forward"
            case .app: "Open App"
            default: approveFallback
            }
        }
    }

    // MARK: - Control

    nonisolated public enum Control {
        /// The Settings tab's title (once "Control", U-35).
        public static let title = "Settings"
        public static let pebbleSection = "Pebble"
        /// The permission modes' section (Pebble: "HOW PEBBLE ACTS"). The modes' copy is `ModeCopy`.
        public static let permissions = "How Pebble Acts"
        /// Pebble's composer label: "Permissions: Ask for approval".
        public static func permissionsLabel(_ mode: PermissionMode) -> String { "Permissions: \(mode.copy.name)" }
        public static let modeChangeNote =
            "Changing how Pebble acts asks for Face ID. Pebble won't change it while a task runs."
        /// "Runs without asking: ..." as Pebble's Settings writes it.
        public static func runsWithoutAskingLine(_ mode: PermissionMode) -> String {
            "\(ModeCopy.runsWithoutAskingHeading): \(mode.copy.runsWithoutAsking)"
        }
        /// "Always asks: ..." as Pebble's Settings writes it.
        public static func alwaysAsksLine(_ mode: PermissionMode) -> String {
            "\(ModeCopy.alwaysAsksHeading): \(mode.copy.alwaysAsks)"
        }
        /// The companion's line when Full access is on, before `ModeCopy` full's runs-without-asking.
        public static let fullAccessOn = "Full access is on."
        /// Pebble's Settings note under Full access, word for word.
        public static let fullAccessWarning =
            "Full access increases the impact of mistakes and prompt injection. Pebble checks each step that would ask against your own messages and runs only what they ask for, never spending money; the check, like AgentGuard, can be wrong and cannot guarantee that every step is safe."
        /// Pebble's companion never widens authority ("Open the workspace to turn this on."); the phone's wording.
        public static let widenOnMac = "Open Pebble on your Mac to turn this on."
        public static let fastReplies = "Fast Replies"
        /// Pebble's Settings › Models names for each choice.
        public static func fastRepliesName(_ value: FastReplies) -> String {
            switch value {
            case .off: "Off"
            case .followUps: "Follow-up messages"
            case .longTasks: "Follow-ups and long tasks"
            case .always: "Always"
            }
        }
        public static func fastRepliesDetail(_ value: FastReplies) -> String {
            switch value {
            case .off: "Every request at the standard speed."
            case .followUps: "Fast for every request after your first message in a conversation."
            case .longTasks: "Also Fast from the fourth step of a long first task. The default."
            case .always: "Fast for every request."
            }
        }
        /// Pebble's Settings › Models note, word for word.
        public static let fastRepliesNote =
            "Uses OpenAI's Fast tier with your ChatGPT sign-in: the same model, served faster. OpenAI prices Fast at twice the standard rate for API use and may count it against your plan's limits faster. Other providers are unaffected."
        public static let model = "Model"
        public static let effort = "Effort"
        public static let noModel = "No model connected"
        /// Pebble's words for an effort level, as its window's effort menu shows them; an unknown level as Pebble sent it.
        public static func effortName(_ level: String) -> String {
            switch level {
            case "default": "Default"
            case "quick": "Quick answer"
            case "think": "Think deeper"
            case "none": "No reasoning"
            case "minimal": "Minimal"
            case "low": "Low"
            case "medium": "Medium"
            case "high": "High"
            case "xhigh": "Extra high"
            case "max": "Maximum"
            default: level
            }
        }
        /// After the effort Pebble recommends for the model, in its menu.
        public static let recommended = "Recommended"
        /// Why the conversation's model and effort can't change now (Pebble refuses while a task runs).
        public static let modelWhileWorking = "Pebble is working. Stop the task to change the model or effort."
        /// The effort of a model without an effort control (Pebble's window, word for word but plainer).
        public static let effortLocked = "This model has no effort control, so the provider's default is used."
        /// What a change here does: the model and effort are Pebble's, for every conversation.
        public static let modelForAllChats = "Changes the model Pebble uses in every conversation."
        public static let effortForAllChats = "Changes the effort Pebble uses in every conversation."
        public static let sharedWindows = "Shared Windows"
        public static let sharedWindowsEmpty = "Pebble isn't using any of your windows."
        public static let revoke = "Revoke"
        public static let revokeHint = "Pebble stops using this window at once"
        public static let toolbox = "Toolbox"
        public static let toolboxEmpty = "Pebble hasn't kept any tools yet."
        public static let remove = "Remove"
        public static let schedules = "Schedules"
        public static let schedulesEmpty = "No schedules."
        public static let pauseSchedule = "Pause"
        public static let resumeSchedule = "Resume"
        public static let notYet = "Pebble Remote can't show this yet."
        public static let stopEverything = "Stop Everything"
        public static let stopEverythingNote = "Stops every task Pebble is running. Steps that already ran aren't undone."
        public static let stopEverythingConfirm = "Stop Everything Pebble Is Doing?"
        public static let stopEverythingConfirmButton = "Stop Everything"
        public static let cancel = "Cancel"
        public static let connection = "Connection"
        public static let settings = "Settings"
    }

    // MARK: - Stealth Lockdown (Pebble's words, word for word: stealthVeil.ts and App.vue)

    nonisolated public enum Stealth {
        public static let name = "Stealth Lockdown"
        public static let description =
            "Keeps Pebble out of screen shares and recordings, and keeps the companion with you over the app you're in."
        /// `STEALTH_ON_TEXT`
        public static let onText = "On. Pebble is hidden from screen capture. Find it in the menu bar."
        /// `STEALTH_OFF_TEXT`
        public static let offText = "Off. Pebble shows in screen shares, the Dock and ⌘Tab as usual."
        /// `STEALTH_HONEST` (D47): shown under the switch, always, word for word.
        public static let honest =
            "Hidden from screen capture and screen sharing, not from a camera, a capture card or a process list. Exams and interviews that forbid assistants still forbid it."
    }

    // MARK: - Settings

    nonisolated public enum Settings {
        public static let pairedMac = "Paired Mac"
        public static func pairedOn(_ date: Date) -> String {
            pairedOn(date.formatted(date: .abbreviated, time: .omitted))
        }
        public static func pairedOn(_ date: String) -> String { "Paired \(date)" }
        public static let forgetMac = "Forget This Mac"
        public static let forgetConfirm =
            "This iPhone stops controlling Pebble on this Mac, and your Mac stops accepting it. If your Mac can't be reached now, remove this iPhone there too, in Pebble's Settings › iPhone. You can pair again any time."
        public static let forgetConfirmButton = "Forget Mac"
        public static func forgetTitle(_ mac: String) -> String { "Forget \(mac)?" }
        public static let security = "Security"
        public static let unlockWithFaceID = "Unlock with Face ID"
        public static let unlockWithFaceIDNote =
            "Pebble Remote asks for Face ID when it opens and when you come back to it."
        /// Apple asks apps to follow the system's appearance. These exist only if the person wants an override.
        public static let appearance = "Appearance"
        public static let appearanceSystem = "System"
        public static let appearanceLight = "Light"
        public static let appearanceDark = "Dark"
        public static let about = "About"
        /// The avatar engine's credit, in Pebble's own words and place (App.vue's About, 2.0.0): the pebble is ported
        /// from it (MIT; the full notice is in AvatarShape.swift).
        public static let avatarCredit = "Avatar engine: bloub by Jérémy Perret (MIT)"
        public static let appVersion = "Pebble Remote"
        public static let pebbleVersion = "Pebble on your Mac"
        public static func version(_ version: String, build: String) -> String { "Version \(version) (\(build))" }
        public static let build = "This Build"
        /// "This build expires Tue 4 Nov, 09:12": an exact date from the build's own provisioning profile.
        public static func expires(_ date: Date) -> String {
            expires(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
        }
        public static func expires(_ date: String) -> String { "This build expires \(date)" }
        public static func expiresIn(days: Int) -> String {
            switch days {
            case ..<1: "This build expires today"
            case 1: "This build expires tomorrow"
            default: "This build expires in \(days) days"
            }
        }
        public static let expired = "This build has expired"
        public static let expiryUnknown = "This build's expiry date isn't known"
        public static let renewHow =
            "To renew it, connect this iPhone to your Mac, open the project in Xcode and press Run. Your pairing and settings stay."
        public static let reminderTitle = "Pebble Remote expires tomorrow"
        public static let reminderBody = "Open the project in Xcode and press Run to keep using it."
        public static let demo = "Demo"
        public static let leaveDemo = "Leave the Demo"
        public static let demoNote = "You're trying a pretend Pebble on this iPhone. Nothing reaches your Mac."
    }

    // MARK: - Pairing

    nonisolated public enum Pairing {
        public static let title = "Pair with Your Mac"
        public static let intro = "Pebble Remote lets you follow and steer Pebble on your Mac from this iPhone."
        public static let howTo =
            "On your Mac, open Pebble and show the pairing code. Then paste the link it copies, or scan the code. It works once, for 5 minutes. Your Mac then asks you to confirm a six-digit code."
        public static let pasteLink = "Paste Link"
        public static let pasteHint = "Copy the link on your Mac, then paste it here."
        public static let scanCode = "Scan Code"
        public static let scanTitle = "Scan the Code"
        public static let scanHint = "Point the camera at the code Pebble shows on your Mac."
        public static let enterByHand = "Enter the Link"
        public static let linkPlaceholder = "pebble-remote://pair?…"
        public static let tryDemo = "Try the Demo"
        public static let tryDemoHint = "A pretend Pebble on this iPhone. Nothing reaches your Mac."
        public static let pairing = "Pairing with your Mac"
        public static func paired(_ mac: String) -> String { "Paired with \(mac)" }
        public static let notALink = "That isn't a pairing link from Pebble. Copy it again on your Mac."
        public static let nothingToPaste = "There's no pairing link to paste. Copy it on your Mac first."
        public static let cameraDenied =
            "Pebble Remote can't use the camera. Allow it in Settings, or paste the link instead."
        public static let cameraUnavailable = "This iPhone can't scan codes now. Paste the link instead."
        public static let openSettings = "Open Settings"
        public static func confirm(_ mac: String) -> String { "Pair with \(mac)?" }
        public static let confirmNote =
            "Pair only with a Mac you own. Pebble Remote will see and steer Pebble on it, and every approval asks for Face ID."
        public static func confirmReplaces(_ current: String) -> String {
            "This iPhone stops controlling Pebble on \(current)."
        }
        /// A link with the paired Mac's id but another key (security review 2026-10-30, S-04).
        public static func confirmNewKey(_ current: String) -> String {
            "This link gives a different key than \(current) used before. Pair only if you just reset Pebble Remote on that Mac. If you didn't, cancel: the link may not come from your Mac."
        }
        public static let pairButton = "Pair"
        public static let cancel = "Cancel"

        // Confirming the pairing on the Mac (X-1): the phone shows six digits, the Mac shows the same six, and the
        // person confirms on the Mac.
        public static let codeTitle = "Confirm on Your Mac"
        public static let codePrompt = "Check that your Mac shows the same code, then confirm on your Mac."
        public static let codeMismatch = "If the codes are different, don't confirm. Cancel on your Mac instead."
        public static let codeWaiting = "Waiting for you to confirm on your Mac"
        public static let codeTimeLimit = "Your Mac waits for 2 minutes."
        /// VoiceOver's name for the six digits, which it reads one by one. (The pairing link's own code is "the pairing
        /// code" in the how-to above, so this one is the confirmation code.)
        public static let codeLabel = "Confirmation code"
        /// The pairing stopped after the code was shown: cancelled on the Mac, nothing within its 2 minutes, or a link that
        /// had been used or had expired (the phone cannot tell which). The link is spent, so the next step is a new one.
        public static let notConfirmed =
            "Pairing wasn't confirmed on your Mac. It was cancelled, 2 minutes passed, or the link had expired or was already used. Show a new pairing link on your Mac, then pair again."
    }

    // MARK: - Face ID: the sentence Face ID shows, the lock, and the app's usage description

    nonisolated public enum FaceID {
        /// For Info.plist `NSFaceIDUsageDescription` (lane E copies it there).
        public static let usageDescription =
            "Pebble Remote uses Face ID before it approves Pebble's actions, and to unlock the app if you turn that on."
        /// Approving one card: what approving does and the exact thing, shortened ("Run Command: npm test").
        public static func approve(_ kind: CardKind, detail: String? = nil) -> String {
            let verb = Reviews.approve(kind)
            if let detail = shortened(detail) { return "\(verb): \(detail)" }
            return "\(verb) for Pebble"
        }
        /// Approving several cards at once (one Face ID check covers up to 30 s).
        public static func approveMany(_ count: Int) -> String { "Approve \(count) actions for Pebble" }
        public static func changeMode(to mode: PermissionMode) -> String { "Switch Pebble to \(mode.copy.name)" }
        public static let keepAwakeOnBattery = "Keep your Mac awake on battery"
        public static func pair(_ mac: String) -> String { "Pair this iPhone with \(mac)" }
        // The lock
        public static let unlock = "Unlock Pebble Remote"
        public static let locked = "Pebble Remote is locked"
        public static let unlockButton = "Unlock"
        /// The passcode prompt's sentence.
        public static let lockReason = "Unlock Pebble Remote to control Pebble on your Mac."
        public static let lockFailed = "That didn't unlock it. Try again."
        public static let turnOffLockReason = "Turn off the Face ID lock"
        public static let unavailable =
            "Face ID isn't available, so Pebble Remote can't approve actions. Turn on Face ID or a passcode in Settings."
        public static let notConfirmed = "Face ID didn't confirm it's you, so nothing was approved."
        /// VoiceOver hint on a control whose change asks for Face ID.
        public static let asksFirst = "Asks for Face ID first"
        /// While a guarded change waits for Face ID and Pebble's answer.
        public static let waiting = "Waiting for Face ID and Pebble"

        static func shortened(_ text: String?, limit: Int = 60) -> String? {
            guard let text else { return nil }
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { return nil }
            return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
        }
    }

    // MARK: - The unlock: Face ID before Pebble acts (claude-w's C1)

    /// Reading needs no Face ID; anything that makes Pebble act (sending, approving, changing settings) needs an unlock
    /// from the last few minutes (15 unless the person changed it on the Mac).
    nonisolated public enum Unlock {
        public static let title = "Face ID Before Pebble Acts"
        /// The explanation, with the window the Mac reports (`welcome.unlock_seconds` when it arrives).
        public static func explanation(minutes: Int) -> String {
            "You can read along at any time. Before Pebble acts on anything you send or change from this iPhone, Face ID unlocks it for \(Unlock.minutes(minutes))."
        }
        public static let why =
            "In Full access Pebble acts on your messages without asking, so a message from this iPhone counts as much as an approval."
        /// The Face ID sentence.
        public static let reason = "Let Pebble act on what you send from this iPhone"
        public static let button = "Unlock"
        /// A call came back `unlock_required`.
        public static let required = "Unlock with Face ID to let Pebble act on what you send."
        public static let locked = "Locked. You can read along; Face ID unlocks acting."
        /// "Unlocked for 12 more minutes."
        public static func remaining(minutes: Int) -> String {
            minutes <= 1 ? "Unlocked for 1 more minute." : "Unlocked for \(minutes) more minutes."
        }
        static func minutes(_ count: Int) -> String { count == 1 ? "1 minute" : "\(count) minutes" }
    }

    // MARK: - Privacy strings for Info.plist (lane E copies them there)

    nonisolated public enum Privacy {
        public static let camera = "Pebble Remote uses the camera only to scan the pairing code on your Mac."
        public static let localNetwork = "Pebble Remote connects to Pebble on your Mac over your local network."
    }

    // MARK: - Connection

    nonisolated public enum Connection {
        public static let title = "Connection"
        public static let connecting = "Connecting to your Mac"
        public static let connected = "Connected"
        public static func reconnecting(attempt: Int?) -> String {
            guard let attempt, (2...99).contains(attempt) else { return "Reconnecting to your Mac" }
            return "Reconnecting to your Mac (try \(attempt))"
        }
        public static let notConnected = "Not connected"
        public static let route = "Route"
        public static let roundTrip = "Round trip"
        public static let address = "Address"
        public static let addresses = "Addresses"
        /// The Mac side's own version row.
        public static let remoteOnMac = "Remote on your Mac"
        public static let connectedSince = "Connected since"
        public static let routeLocal = "Local network"
        public static let routeTailscale = "Tailscale"
        public static let routeOther = "Internet"
        public static let routeDemo = "Demo"
        /// A measured round trip: "6 ms", "<1 ms".
        public static func milliseconds(_ ms: Double) -> String {
            guard ms.isFinite, ms >= 0 else { return "" }
            if ms < 1 { return "<1 ms" }
            return "\(Int(min(ms, 9e15).rounded())) ms"
        }
        /// Shown once: what happens while the app is closed (a free account has no push notifications).
        public static let whileClosed =
            "While Pebble Remote is closed, it doesn't hear from your Mac. When you open it again, it catches up on everything that happened."
        public static let pairAgain = "Pair Again"
        public static let tryAgain = "Try Again"

        // Why a connection needs the person
        public static let revoked = "This iPhone was removed from Pebble on your Mac. Pair again to use it."
        public static let unknownDevice = "Your Mac doesn't know this iPhone any more. Pair again to use it."
        /// The Mac didn't show the key this iPhone paired with. Never "pair again to be safe": that could pair with the
        /// wrong Mac.
        public static let identityChanged =
            "Your Mac couldn't prove it's the Mac you paired with, so Pebble Remote didn't connect. Pair again only if you reset remote access in Pebble on your Mac."
        public static let pebbleTooOld = "Pebble on your Mac is too old for this app. Update Pebble, then try again."
        public static let pebbleNotRunning = "Pebble isn't open on your Mac. Open it, then try again."
        public static let unreachable =
            "Can't reach your Mac. Check that it's awake, and on the same network or on Tailscale."
        public static let localNetworkDenied =
            "Pebble Remote can't reach your Mac because it isn't allowed on your local network. Turn on Pebble Remote in Settings → Privacy & Security → Local Network, then come back."
    }

    // MARK: - Errors

    nonisolated public enum Errors {
        /// Words for a content-free code from the client (`RemoteCallError.transport(code)`), the bridge's `bye`, or a
        /// refusal, when the bridge sent no words of its own. Nil for a code this version doesn't know: then show the
        /// bridge's own words, or `generic`.
        public static func forCode(_ code: String) -> String? {
            switch code {
            // The client (lane B)
            case "connection_lost": connectionDropped
            case "bridge_restarted": bridgeRestarted
            case "too_large": tooLarge
            case "bad_params": badParams
            // Pairing (lane B)
            case "unreachable": Connection.unreachable
            case "local_network": Connection.localNetworkDenied
            case "pin_mismatch": Connection.identityChanged
            case "wrong_bridge": wrongMac
            case "bad_version": versionMismatch
            case "biometry_unavailable": FaceID.unavailable
            case "keys_unavailable": keysUnavailable
            case "protocol": unreadable
            // The bridge's `bye` codes
            case "unknown_device": Connection.unknownDevice
            case "revoked": Connection.revoked
            case "bad_signature": badSignature
            case "replaced": replaced
            case "busy": busy
            // The Mac's `bye` `bad_code` and the phone's own wait running out: after the code was shown, both mean the
            // pairing was not confirmed.
            case "bad_code", "not_confirmed": Pairing.notConfirmed
            // Refusals
            case "unlock_required": Unlock.required
            case "proof_required", "bad_proof": proofRefused
            case "not_allowed": notAllowed
            case "pebble_offline": Connection.pebbleNotRunning
            case "not_connected": notConnected
            case "timed_out": timedOut
            case "not_offered": notAvailable
            case "unreadable": unreadable
            default: nil
            }
        }

        public static let bridgeRestarted = "Pebble on your Mac restarted, so Pebble Remote read everything again."
        public static let tooLarge = "That's too large to send to your Mac in one go."
        public static let badParams = "Pebble Remote couldn't put that request together, so nothing was sent."
        public static let wrongMac =
            "The Mac that answered isn't the one in the pairing link, so Pebble Remote didn't pair. Show a new code on your Mac."
        public static let versionMismatch =
            "Pebble on your Mac and this app don't speak the same version. Update both, then try again."
        public static let keysUnavailable =
            "Pebble Remote couldn't make its keys on this iPhone. Check that the iPhone has a passcode and Face ID, then pair again."
        public static let unreadable =
            "Your Mac answered in a way this version of Pebble Remote can't read. Update Pebble Remote and Pebble, then try again."
        public static let badSignature = "Your Mac couldn't check this iPhone's signature. Pair again to use it."
        public static let replaced = "This iPhone connected to your Mac again, so this older connection closed."
        public static let busy = "Your Mac is busy with another connection. Try again in a moment."
        public static let proofRefused = "Your Mac didn't accept this iPhone's Face ID confirmation, so nothing happened. Try again."
        public static let notAllowed = "That can only be done on your Mac."

        public static let notConnected = "Not connected to your Mac. Pebble Remote keeps trying."
        /// Honest: after a timeout the phone can't know whether the Mac did it.
        public static let timedOut =
            "Your Mac didn't answer in time, so Pebble Remote can't tell whether it happened. Check the conversation before trying again."
        public static let connectionDropped = "The connection to your Mac dropped. Pebble Remote is reconnecting."
        public static let notAvailable = "Pebble on your Mac doesn't offer this yet."
        public static let generic = "Pebble Remote couldn't do that."
        public static let approveFailed = "The approval didn't go through. The card is still waiting."
        public static let faceIDFailed = FaceID.notConfirmed
        public static let ok = "OK"
    }

    // MARK: - Empty and unavailable states (titles in title style, for ContentUnavailableView)

    nonisolated public enum Empty {
        public static let noChatsTitle = Chats.emptyTitle
        public static let noChatsDescription = Chats.emptyDetail
        public static let noReviewsTitle = Reviews.emptyTitle
        public static let noReviewsDescription = Reviews.emptyDescription
        public static let notPairedTitle = "Not Paired"
        public static let notPairedDescription = "Pair with Pebble on your Mac to see what it's doing."
        public static let notConnectedTitle = "Not Connected"
        public static let notConnectedDescription = "Pebble Remote shows what Pebble is doing once it reaches your Mac."
        public static let pebbleClosedTitle = "Pebble Isn't Open"
        public static let pebbleClosedDescription = Home.pebbleNotOpenDetail
        public static let nothingRunningTitle = "Nothing Running"
        public static let nothingRunningDescription = Home.idleDetail
        public static let noSharedWindowsTitle = "No Shared Windows"
        public static let noSharedWindowsDescription = Control.sharedWindowsEmpty
        public static let noToolsTitle = "No Tools Yet"
        public static let noToolsDescription = Control.toolboxEmpty
        public static let noSchedulesTitle = "No Schedules"
        public static let noSchedulesDescription = "Schedules you set up in Pebble on your Mac show up here."
    }

    // MARK: - VoiceOver

    nonisolated public enum Accessibility {
        public static let avatar = "Pebble"
        public static let runningFor = "Running for"
        public static func waitingItems(_ count: Int) -> String {
            count == 1 ? "1 item needs your review" : "\(count) items need your review"
        }
        public static let streamingCaret = "Pebble is still writing"
        /// A message of yours, read aloud: "You: ...".
        public static func fromYou(_ text: String) -> String { "\(Conversation.you): \(text)" }
        public static let exactDetailHint = "The exact text Pebble will use"
    }
}

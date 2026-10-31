import Foundation
import PebbleProtocol

// The P1 screens' strings, under the names lane E's screens already use (formerly `PendingCopy` in PebbleRemoteUI):
// switching is `PendingCopy.` -> `AppCopy.`, except `Schedules.resumeMessage`, which takes plain values here.
// Pebble's own words are defined once, in `SettingsCopy`, and only named here.
extension AppCopy {
    /// Your Mac's screen (claude-w's C3).
    nonisolated public enum MacScreen {
        public static let title = "Mac Screen"
        public static let imageLabel = "Your Mac's screen"
        public static let displayPicker = "Display"
        /// `number` counts from 1.
        public static func display(_ number: Int) -> String { "Display \(number)" }
        public static let refresh = "Refresh"
        public static func takenAt(_ time: String) -> String { "Taken at \(time)" }
        public static let nothingCaptured = "Your Mac sent no picture. Try again."
        /// What happens to the picture.
        public static let note = SettingsCopy.Screenshot.note
        public static let stealthNote = SettingsCopy.Screenshot.stealthNote
    }

    /// Pebble's own settings (Permissions, Memory, Appearance, Git decisions), as the screens name them.
    nonisolated public enum PebbleSettings {
        public static let availableTools = SettingsCopy.Permissions.toolsSection
        public static let toolOrder = SettingsCopy.Permissions.toolOrder
        public static func tool(_ id: String) -> String { SettingsCopy.Permissions.toolName(id) }
        public static func toolNote(_ id: String) -> String? { SettingsCopy.Permissions.toolNote(id) }
        /// The phone's version of Pebble's note ("this settings screen" becomes Pebble's settings here or on the Mac).
        public static let toolsNote = SettingsCopy.Permissions.toolsNote
        public static let protectedPlaces = SettingsCopy.Permissions.protectedPlaces
        public static let memory = SettingsCopy.Memory.section
        public static let rememberContext = SettingsCopy.Memory.enabled
        public static let rememberContextDetail = SettingsCopy.Memory.enabledDetail
        public static let memoryLayers = "Memory Layers"
        public static let memoryNote = SettingsCopy.Memory.layersNote
        public static let layerSwitch = SettingsCopy.Memory.layerSwitch
        public static func layer(_ id: String) -> String { SettingsCopy.Memory.layerName(id) }
        /// Pebble's appearance settings change the Mac; the phone follows its own system appearance.
        public static let appearance = "Appearance on Your Mac"
        public static let theme = "Theme"
        public static func themeChoice(_ id: String) -> String { SettingsCopy.Appearance.theme(id) }
        public static let reduceMotion = SettingsCopy.Appearance.reduceMotion
        public static let reduceMotionDetail = SettingsCopy.Appearance.reduceMotionDetail
        public static let companion = "Companion"
        public static let followPointer = SettingsCopy.Appearance.followPointer
        public static let followPointerDetail = SettingsCopy.Appearance.followPointerDetail
        public static let reactions = SettingsCopy.Appearance.reactions
        public static let reactionsDetail = SettingsCopy.Appearance.reactionsDetail
        /// Pebble's line for a companion switch while Reduce motion is on.
        public static let offWhileReduced = SettingsCopy.Appearance.followPointerOffDetail
        public static let reactionsOffWhileReduced = SettingsCopy.Appearance.reactionsOffDetail
        public static let statusWords = SettingsCopy.Appearance.statusWords
        public static let statusWordsDetail = SettingsCopy.Appearance.statusWordsDetail
        public static func statusWordsChoice(_ id: String) -> String { SettingsCopy.Appearance.statusWordsChoice(id) }
        public static let uiGuidance = SettingsCopy.Appearance.uiGuidance
        public static let uiGuidanceDetail = SettingsCopy.Appearance.uiGuidanceDetail
        public static let on = "On"
        public static let off = "Off"
        public static let gitDecisions = SettingsCopy.GitDecisions.section
        public static let gitDecisionOrder = SettingsCopy.GitDecisions.order
        public static func gitDecision(_ id: String) -> String { SettingsCopy.GitDecisions.name(id) }
        public static func gitDecisionDetail(_ id: String) -> String? { SettingsCopy.GitDecisions.detail(id) }
        public static let gitDecisionsNote = SettingsCopy.GitDecisions.note
    }

    /// Pebble's Recently Deleted conversations.
    nonisolated public enum Deleted {
        public static let title = SettingsCopy.Conversations.recentlyDeleted
        public static let emptyTitle = "Nothing Recently Deleted"
        /// Pebble's line under the empty list.
        public static let emptyDetail = SettingsCopy.Conversations.empty
        public static let delete = SettingsCopy.Conversations.delete
        public static let restore = SettingsCopy.Conversations.restore
        public static let deleteForGood = SettingsCopy.Conversations.purgeButton
        public static let confirmTitle = "Delete This Conversation for Good?"
        /// Pebble's words after its question: what stays, too.
        public static let confirmMessage =
            "It cannot be restored. Copies made earlier in upgrade backups, install backups and the old folder stay until you remove them."
        /// Pebble's line: deleted for good after the date.
        public static func deletesOn(_ date: String) -> String { "Deleted for good after \(date)" }
        public static func deleted(_ date: String) -> String { "Deleted \(date)" }
    }

    /// The Mac's notifications, Pebble's words (NotificationSettings.vue).
    nonisolated public enum Notifications {
        public static let title = SettingsCopy.Notifications.section
        public static let show = SettingsCopy.Notifications.enabled
        public static let notifyAbout = SettingsCopy.Notifications.notifyAbout
        public static let replies = SettingsCopy.Notifications.replies
        public static let kindOrder = SettingsCopy.Notifications.kindOrder
        public static func kind(_ id: String) -> String { SettingsCopy.Notifications.kind(id) }
        public static let preview = SettingsCopy.Notifications.previewSection
        public static let previewOrder = SettingsCopy.Notifications.previewOrder
        /// A preview choice's name; an unknown one shows as Pebble sends it.
        public static func previewName(_ id: String) -> String {
            SettingsCopy.Notifications.previewOrder.contains(id) ? SettingsCopy.Notifications.preview(id) : id
        }
        public static func previewNote(_ id: String) -> String? {
            SettingsCopy.Notifications.previewOrder.contains(id) ? SettingsCopy.Notifications.previewNote(id) : nil
        }
        /// Pebble's first sentence about grouping, word for word.
        public static let note =
            "Several updates from one schedule within a minute share one banner, and after three banners in ten minutes Pebble shows one summary."
        public static let quietHoursNote = SettingsCopy.Notifications.quietNote
        public static let phoneNote = SettingsCopy.Notifications.phoneNote
    }

    /// A new schedule from the phone.
    nonisolated public enum NewSchedule {
        public static let title = "New Schedule"
        public static let add = "New Schedule"
        public static let conversation = "Conversation"
        public static let name = "Name"
        public static let task = "What Pebble does each time"
        public static let repeats = "Repeat"
        public static let once = "Once"
        public static let daily = "Every Day"
        public static let everyFewHours = "Every Few Hours"
        public static let at = "At"
        public static func everyHours(_ hours: Int) -> String { hours == 1 ? "Every Hour" : "Every \(hours) Hours" }
        public static let review = "Review"
        public static let create = "Create"
        public static let nextRuns = "Next Runs"
        public static let reviewNote = "It runs with Pebble's settings as they are now. Creating it asks for Face ID."
        /// Pebble's own rule for every schedule, shown with the review.
        public static let rules = SettingsCopy.Schedules.note
    }

    /// A run in detail ("What Pebble did").
    nonisolated public enum RunDetails {
        public static let title = RunCopy.whatPebbleDid
        /// Pebble's names for the step list while it runs and after.
        public static let doing = "What Pebble is doing"
        public static let did = RunCopy.whatPebbleDid
        public static let steps = "Steps"
        /// Pebble's heading, word for word: the summary is the model's, not Pebble's record.
        public static let reasoning = "Pebble's reasoning, summarised by the model"
    }

    /// Windows and tabs Pebble may use.
    nonisolated public enum Sessions {
        public static func until(_ time: String) -> String { "Until \(time)" }
        public static let title = SettingsCopy.ScreenSessions.section
        public static let note = SettingsCopy.ScreenSessions.note
    }

    /// Pebble's Toolbox, Pebble's words where it has them (App.vue's toolbox cards).
    nonisolated public enum Toolbox {
        public static let asks = "Pebble Asks"
        public static let removed = "Recently Removed"
        public static let putBack = SettingsCopy.Toolbox.putBack
        public static let keep = "Keep"
        /// Pebble's word for not keeping a tool it asked about.
        public static let dontKeep = "Discard"
        public static let removeConfirm = "Remove this tool from Pebble's Toolbox?"
        public static let keepConfirm = "Keep this tool in Pebble's Toolbox?"
        public static let kept = "Kept in Pebble's Toolbox"
        public static func asksBecause(_ why: String) -> String { "Pebble asks because \(why)." }
        public static let keptNote = "Pebble kept this tested calculation on its own. Remove it if you don't want it."
        public static let removeNote = "You asked to remove it. Nothing is removed until you choose Remove."
        public static let keptDone = "Kept in the Toolbox"
        public static let discarded = "Discarded"
        public static let keepIt = "Keep It"
    }

    /// Pebble's schedules.
    nonisolated public enum Schedules {
        public static let notices = "Notices"
        public static func next(_ when: String) -> String { "Next run \(when)" }
        public static func resumeTitle(_ name: String) -> String { "Resume \u{201C}\(name)\u{201D}?" }
        public static func deleteTitle(_ name: String) -> String { "Delete the schedule \u{201C}\(name)\u{201D}?" }
        /// What resuming runs with, from Pebble's review: "It resumes with Pebble's current settings. Ask for
        /// approval, <model>, next run 30 Oct, 09:00."
        public static func resumeMessage(mode: PermissionMode?, modelName: String?, nextRun: Date?) -> String {
            var parts: [String] = []
            if let mode { parts.append(mode.copy.name) }
            if let modelName, !modelName.isEmpty { parts.append(modelName) }
            if let nextRun { parts.append("next run \(nextRun.formatted(date: .abbreviated, time: .shortened))") }
            let detail = parts.isEmpty ? "" : " " + parts.joined(separator: ", ") + "."
            return "It resumes with Pebble's current settings.\(detail)"
        }
        public static let note = SettingsCopy.Schedules.note
    }

    /// The phones paired with the Mac.
    nonisolated public enum Devices {
        /// Pebble's own heading in its Settings › iPhone (RemoteSettings.vue, 1.9.29: "Paired iPhones"); the lead's
        /// decision, 23:03.
        public static let title = "Paired iPhones"
        public static func thisPhone(_ name: String) -> String { "\(name) (This iPhone)" }
        public static func lastSeen(_ when: String) -> String { "Last seen \(when)" }
        public static func remove(_ name: String) -> String { "Remove \(name)? It stops controlling Pebble on your Mac." }
        public static let removeThisPhone = "Remove this iPhone? It stops controlling Pebble until you pair it again."
    }

    /// Starting a conversation in a project Pebble already knows.
    nonisolated public enum Projects {
        public static let project = "Project"
        public static let none = "No Project"
    }

    /// Attaching a photo from the phone to a conversation.
    nonisolated public enum Attach {
        public static let photo = "Attach Photo"
        public static let unreadable = "Pebble Remote couldn't read that photo. Try another one."
    }
}

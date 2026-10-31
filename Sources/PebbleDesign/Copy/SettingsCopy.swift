import Foundation
import PebbleProtocol

/// Pebble's own settings, which the phone now controls (contract v0.2, R2), in Pebble's words: word for word from
/// `src/components/AdvancedSettings.vue`, `src/App.vue` (Appearance), `NotificationSettings.vue`,
/// `StorageSettings.vue`, `ScreenSessions.vue`, `CompanionWorkflows.vue` and `backend/pebble/memory.py`
/// (`PebbleParityTests` compares them). Setting names and explanations keep Pebble's sentence case; section headers
/// (upper case on the Mac) and buttons take Apple's title style.
///
/// Where Pebble's sentence names a place on the Mac ("this settings screen", "this device", "Settings → Data &
/// storage"), the Mac's sentence stays in a constant ending in `OnMac`, and the phone shows a variant that changes
/// only the place.
nonisolated public enum SettingsCopy {
    // MARK: - Permissions: the mode and the tool switches (AdvancedSettings.vue, tab "permissions")

    nonisolated public enum Permissions {
        /// "HOW PEBBLE ACTS"
        public static let modeSection = "How Pebble Acts"
        /// "AVAILABLE TOOLS"
        public static let toolsSection = "Available Tools"
        /// The tool switches, in Pebble's order (`state.settings.permissions.tools`).
        public static let toolOrder = ["files", "edits", "tests", "apps", "web", "terminal", "plugins", "views", "screen", "capture"]

        /// `toolLabels`: a tool switch's name; an unknown tool shows its key, as Pebble does.
        public static func toolName(_ key: String) -> String {
            switch key {
            case "files": "Read project files"
            case "edits": "Edit project files"
            case "tests": "Run isolated tests"
            case "apps": "Open installed apps"
            case "web": "Search and read the web"
            case "terminal": "Use terminal commands"
            case "plugins": "Use connectors you enabled"
            case "views": "Create interactive views"
            case "screen": "Screen control: app windows and Chrome tabs you share"
            case "capture": "Take screenshots when a task needs them"
            default: key
            }
        }

        /// The explanation under a tool switch, where Pebble has one.
        public static func toolNote(_ key: String) -> String? {
            switch key {
            case "web": webDestination
            case "terminal": terminalNote
            case "capture": captureNote
            case "screen": screenNote
            default: nil
            }
        }

        /// `WEB_DESTINATION`
        public static let webDestination =
            "Searches send your search words to Microsoft Bing (its RSS results feed). Pages Pebble reads are fetched from their own sites."
        /// `TERMINAL_NOTE`
        public static let terminalNote =
            "In a conversation without a project, commands run in a sandbox that writes only in ~/Pebble Workbench and has no network. Pebble asks before it writes elsewhere or reaches a website."
        /// `CAPTURE_NOTE`
        public static let captureNote =
            "macOS asks too: allow Pebble in System Settings > Privacy & Security > Screen & System Audio Recording. From time to time macOS also asks whether Pebble may “bypass the system private window picker”; choose Allow if you want Pebble to see the windows you share. Pebble takes pictures of a shared window only, never sound."
        /// `SCREEN_NOTE`
        public static let screenNote =
            "App windows also need Pebble in System Settings > Privacy & Security > Accessibility. Pebble uses only the window you allow. Keys of a keypad and squares of a game board are pressed without asking. In Full access Pebble also runs the presses, sends, saves and deletes your messages ask for, and anything that may spend money asks you first; in the other modes anything that may send, buy, delete, save, sign in or share asks you first. A window or site you allow stays allowed in that conversation for up to 15 minutes."
        /// `PROTECTED_PLACES`
        public static let protectedPlaces =
            "Keys and passwords, browser data, Messages, Mail, Pebble's own data, other assistants' sign-ins and your shell history are never read or written, whatever you allow."
        /// The note under the tool switches, as on the Mac.
        public static let toolsNoteOnMac =
            "Only this settings screen can grant access. Documents, web pages, memories, models and extensions cannot change permissions. Changing access takes effect on the next task."
        /// The same note on the phone: only the place changes.
        public static let toolsNote =
            "Only Pebble's settings, on your Mac or here, can grant access. Documents, web pages, memories, models and extensions cannot change permissions. Changing access takes effect on the next task."
        /// Turning a tool on or a wider mode asks for Face ID first.
        public static let widenNeedsFaceID = "Turning on more access asks for Face ID."
        /// Pebble's refusal while a task runs (its controls are disabled then).
        public static let busy = "Available when the task is idle"
        /// The Face ID sentence for turning a tool on.
        public static func enableReason(_ key: String) -> String { "Let Pebble \(lowercasedFirst(toolName(key)))" }

        static func lowercasedFirst(_ text: String) -> String {
            guard let first = text.first else { return text }
            return first.lowercased() + text.dropFirst()
        }
    }

    // MARK: - Memory (AdvancedSettings.vue, tab "memory"; layer names from memory.py)

    nonisolated public enum Memory {
        public static let section = "Memory"
        public static let enabled = "Remember useful context"
        public static let enabledDetailOnMac = "Selective recall across conversations, stored on this device"
        /// On the phone: the memories are on the Mac, not on this iPhone.
        public static let enabledDetail = "Selective recall across conversations, stored on your Mac"
        public static let layersNote =
            "Working context records the task state. Experiences record past requests and what their actions did. The agent can learn attributed source quotes, direct preferences and repeated test recipes. Time-sensitive data expires. Retrieved text never becomes permission."
        public static let layerSwitch = "Learning and recall in this layer"
        public static let candidatesNote =
            "Supported proposals are saved automatically. Conflicting or unsupported proposals stay out of recall."
        /// The six layers, in Pebble's order (settings `memory_layers`).
        public static let layerOrder = ["working", "episodic", "semantic", "procedural", "temporal", "profile"]
        /// A layer's name (memory.py `KINDS`); Pebble's `state.memory.types` names win when present.
        public static func layerName(_ id: String) -> String {
            switch id {
            case "working": "Working context"
            case "episodic": "Past experiences"
            case "semantic": "Facts & knowledge"
            case "procedural": "Procedures"
            case "temporal": "Time-sensitive information"
            case "profile": "Your preferences"
            default: id
            }
        }
        public static let nothingSaved = "Nothing saved here yet."
        public static let forget = "Forget"
        public static let keep = "Keep"
        public static let forgetNote =
            "Nothing is forgotten until you choose Forget. These are records Pebble saved; forgetting one removes it for good."
    }

    // MARK: - Appearance and the companion (App.vue, Settings › Appearance)

    nonisolated public enum Appearance {
        /// "APPEARANCE"
        public static let section = "Appearance"
        public static func theme(_ value: String) -> String {
            switch value {
            case "light": "Light"
            case "dark": "Dark"
            default: "System"
            }
        }
        public static let themeOrder = ["light", "dark", "system"]
        /// The phone's line under the theme: it changes Pebble on the Mac, not this iPhone.
        public static let themeNote = "Changes Pebble's windows on your Mac. Pebble Remote follows this iPhone's appearance."
        public static let reduceMotion = "Reduce motion"
        public static let reduceMotionDetail = "Keep the companion still"
        public static let followPointer = "Follow the pointer"
        public static let followPointerDetail = "The companion's eyes track your pointer"
        public static let followPointerOffDetail = "Off while Reduce motion is on"
        public static let reactions = "Expressive reactions"
        public static let reactionsDetail = "Celebrations, taps and drowsiness; task states always show"
        public static let reactionsOffDetail = "Off while Reduce motion is on; task states always show"
        public static let statusWords = "Status words"
        public static let statusWordsDetail = "What Pebble is doing, from its own activity records"
        /// The status-words choices (`companion.status_words`).
        public static func statusWordsChoice(_ value: String) -> String {
            switch value {
            case "rotate": "Varied"
            case "fixed": "One word"
            case "off": "Hidden"
            default: value
            }
        }
        public static let statusWordsOrder = ["rotate", "fixed", "off"]
        public static let uiGuidance = "UI design guidance"
        public static let uiGuidanceDetail =
            "Offer Pebble's built-in view guidance to larger models when you ask for a view"
    }

    // MARK: - Notifications on the Mac (NotificationSettings.vue)

    nonisolated public enum Notifications {
        public static let section = "Notifications"
        /// The phone's line: these settings are the Mac's banners (Pebble Remote has no push notifications).
        public static let phoneNote =
            "These are your Mac's banners. Pebble Remote shows Pebble's updates while it's open."
        public static let enabled = "Show macOS notifications"
        public static let notifyAbout = "Notify Me About"
        public static let replies = "Replies and cards while Pebble is in the background"
        public static let kindOrder = ["completed", "failed", "action_needed", "monitor_changed"]
        public static func kind(_ key: String) -> String {
            switch key {
            case "completed": "Completed runs"
            case "failed": "Failures"
            case "action_needed": "Requests for your action"
            case "monitor_changed": "Monitor results that changed"
            default: key
            }
        }
        public static let previewSection = "Content Preview"
        public static let previewOrder = ["title", "body", "none"]
        public static func preview(_ key: String) -> String {
            switch key {
            case "body": "Title and a short preview"
            case "none": "No details"
            default: "Title only"
            }
        }
        public static func previewNote(_ key: String) -> String {
            switch key {
            case "body":
                "Up to 140 characters of the run’s answer, without links or control characters. The answer is run output, not a message from Pebble."
            case "none": "Shows only that a schedule has an update."
            default: "Default. Shows which schedule has an update, not what the run said."
            }
        }
        public static let quietSection = "Quiet Hours"
        public static let quiet = "Hold banners during quiet hours"
        public static let from = "From"
        public static let until = "Until"
        public static func timesIn(_ zone: String) -> String { "Times are in \(zone)." }
        public static let quietNote =
            "During quiet hours banners wait. When quiet hours end, Pebble shows one summary. Nothing is dropped, and every update stays in the app."
        public static let groupingNoteOnMac =
            "Several updates from one schedule within a minute share one banner, and after three banners in ten minutes Pebble shows one summary. Banners offer only Open, which opens the conversation; approvals happen only in the Pebble window."
        /// On the phone: approvals also happen here now.
        public static let groupingNote =
            "Several updates from one schedule within a minute share one banner, and after three banners in ten minutes Pebble shows one summary. Banners offer only Open, which opens the conversation; approvals happen in the Pebble window or in Pebble Remote."
        public static let unsaved = "Changes here apply when you save them."
        public static let save = "Save Notification Preferences"
        public static let saved = "Notification preferences saved."
        public static let quietTimesInvalid = "Give quiet hours as 24-hour times such as 22:00."
        public static let quietTimesSame = "Quiet hours need different start and end times."
    }

    // MARK: - Git decisions (settings `git_decisions`; Pebble's words from settings_file.py's schema description)

    nonisolated public enum GitDecisions {
        public static let section = "Git Decisions"
        /// The switches, in Pebble's order (settings_file.py `GIT_DECISIONS`).
        public static let order = ["force_push", "delete_remote_branch", "repository_identity", "clean"]
        /// A switch's name (Pebble's key, in words).
        public static func name(_ key: String) -> String {
            switch key {
            case "force_push": "Force push"
            case "delete_remote_branch": "Delete remote branches"
            case "repository_identity": "Repository identity"
            case "clean": "Clean"
            default: key
            }
        }
        /// What a switch allows, in Pebble's words (the schema's parentheses).
        public static func detail(_ key: String) -> String? {
            switch key {
            case "force_push": "Replace a remote branch's history, with a lease on the commit seen at review"
            case "repository_identity": "This repository's user.name and user.email"
            case "clean": "Delete the untracked files git clean lists"
            default: nil
            }
        }
        /// The note under the switches (the schema's first and last clauses).
        public static let note =
            "Git actions that are your decision, each on unless you turn it off. Forced pushes, deletions and cleans still wait for your review each time."
    }

    // MARK: - Models and effort (App.vue's model picker, AdvancedSettings.vue "YOUR MODELS")

    nonisolated public enum Models {
        /// "YOUR MODELS"
        public static let section = "Your Models"
        public static let model = "Model"
        public static let effort = "Reasoning effort"
        /// `effortLabel`: an effort level's name; an unknown level shows as Pebble sends it.
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
        /// After the model's default effort: "High · recommended".
        public static func effortChoice(_ level: String, recommended: Bool) -> String {
            recommended && level != "default" ? "\(effortName(level)) · recommended" : effortName(level)
        }
        public static let noEffortControl = "This model has no verified effort control; provider default is used."
        public static let effortControls = "Controls this model’s actual reasoning parameter"
        public static let noModel = "No model connected"
        public static let busy = "Available when the task is idle"
    }

    // MARK: - Conversations: delete, Recently deleted, delete for good (App.vue, StorageSettings.vue)

    nonisolated public enum Conversations {
        public static let delete = "Delete"
        public static let recentlyDeleted = "Recently Deleted"
        public static let conversation = "Conversation"
        /// The confirmation before a conversation moves to Recently deleted, as on the Mac.
        public static func moveConfirmOnMac(_ title: String) -> String {
            "“\(title)” moves to Recently deleted, where you can restore it for 30 days. After that it is deleted with its messages, attachments and review history. To delete it at once, use Delete now in Settings → Data & storage."
        }
        /// On the phone: "Delete Now" is in Recently Deleted here.
        public static func moveConfirm(_ title: String) -> String {
            "“\(title)” moves to Recently deleted, where you can restore it for 30 days. After that it is deleted with its messages, attachments and review history. To delete it at once, use Delete Now in Recently Deleted."
        }
        public static let moveButton = "Move to Recently Deleted"
        public static let moved = "Moved to Recently deleted."
        public static let undo = "Undo"
        public static let emptyOnMac =
            "Nothing here. Conversations you delete, in Pebble or by deleting their file in Documents, wait here for 30 days."
        public static let empty = emptyOnMac
        /// "Deleted 28 Oct · deleted for good after 27 Nov".
        public static func trashedLine(deleted: String, deleteAfter: String) -> String {
            "Deleted \(deleted) · deleted for good after \(deleteAfter)"
        }
        public static func trashedLine(deleted: Date, deleteAfter: Date) -> String {
            trashedLine(
                deleted: deleted.formatted(date: .abbreviated, time: .omitted),
                deleteAfter: deleteAfter.formatted(date: .abbreviated, time: .omitted))
        }
        public static let restore = "Restore"
        public static func restored(_ title: String) -> String { "Restored “\(title)”." }
        public static let deleteNow = "Delete Now"
        /// Before deleting for good (Face ID follows).
        public static func purgeConfirm(_ title: String) -> String {
            "Delete “\(title)” for good? It cannot be restored. Copies made earlier in upgrade backups, install backups and the old folder stay until you remove them."
        }
        public static let purgeButton = "Delete for Good"
        public static let keep = "Keep"
        public static func purged(_ title: String) -> String { "Deleted “\(title)” for good." }
        /// The Face ID sentence for deleting for good.
        public static func purgeReason(_ title: String) -> String { "Delete “\(title)” for good" }
        /// Sending into a conversation that is in Recently deleted (the phone's version of Pebble's notice).
        public static let sendIntoTrashed =
            "That conversation is in Recently deleted. Restore it first, or ask Pebble in a new conversation."
    }

    // MARK: - Schedules (CompanionWorkflows.vue)

    nonisolated public enum Schedules {
        public static let section = "Schedules"
        public static let note =
            "Schedules in this chat fire only while the Pebble service is running. Permissions still apply on each run; nothing is approved in advance. Pausing or deleting a schedule never cancels an unrelated run. After sleep, a schedule runs once at its latest missed time unless it skips late times."
        public static let pause = "Pause"
        public static let resume = "Resume"
        public static let resumeNeedsFaceID = "Resuming a schedule asks for Face ID."
        public static let empty = "No schedules."
        public static func nextRun(_ date: Date) -> String {
            "Next run \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        public static let paused = "Paused"
        /// The Face ID sentence for resuming one.
        public static func resumeReason(_ title: String) -> String { "Resume the schedule “\(title)”" }
        /// The Face ID sentence for creating one.
        public static let createReason = "Create a schedule for Pebble"
    }

    // MARK: - Pebble's Toolbox (AdvancedSettings.vue "PEBBLE'S TOOLBOX")

    nonisolated public enum Toolbox {
        /// "PEBBLE'S TOOLBOX"
        public static let section = "Pebble's Toolbox"
        public static let workshopTitle = "Pebble's Workshop."
        public static let workshopNote =
            "When a task needs exact numbers, Pebble writes and runs a little code (Code Mode), and it can turn a calculation it trusts into a tool kept here. Try: “Make a tool that converts Celsius to Fahrenheit and keep it.”"
        public static let note =
            "Small tested calculations Pebble made while working. Pebble keeps one on its own only when it passed every check and always tells you; any other keep asks you first. They run only inside Pebble's sandbox, with no network or files."
        /// "Converts units · kept by Pebble · used 3 times".
        public static func toolLine(purpose: String, keptByPebble: Bool, uses: Int, needsAttention: Bool) -> String {
            "\(purpose) · kept by \(keptByPebble ? "Pebble" : "you") · used \(uses) \(uses == 1 ? "time" : "times")"
                + (needsAttention ? " · needs attention: it failed its re-check and is not used" : "")
        }
        /// "Removed · you can put it back for 4 more minutes".
        public static func removedLine(minutesLeft: Int) -> String {
            let minutes = max(1, minutesLeft)
            return "Removed · you can put it back for \(minutes) more \(minutes > 1 ? "minutes" : "minute")"
        }
        public static let viewCode = "View Code"
        public static let hideCode = "Hide Code"
        public static let remove = "Remove"
        public static let putBack = "Put Back"
        public static let empty = "No kept tools yet."
        public static let emptyAfterRemoval = "No kept tools."
    }

    // MARK: - Windows and tabs Pebble may use (ScreenSessions.vue)

    nonisolated public enum ScreenSessions {
        /// The phone's section name ("Windows Pebble can use" is a retired name: `BannedWords.phrases`).
        public static let section = "Shared Windows and Tabs"
        public static let note =
            "You choose each window or tab Pebble may use; it stays allowed in this conversation for up to 15 minutes, and a message in another conversation ends it (in Full access Pebble allows the ones your messages ask for). Window text is shown as the app or page wrote it; it never gives Pebble permission. At a sign-in, a code or a check, Pebble stops and it's your turn: you finish it yourself, and Pebble never sees what you type."
        public static let empty = "Pebble isn't using any window in this conversation."
        public static let recentlyEnded = "Recently Ended"
        public static let unknownWindow = "Unknown window"
        /// `STATES`
        public static func state(_ key: String) -> String {
            switch key {
            case "active": "Pebble can use it"
            case "handoff": "Your turn"
            case "interrupted": "Paused: the last step has an uncertain outcome"
            case "revoked": "Ended by you"
            case "expired": "Time ran out"
            case "restarted": "Ended when Pebble restarted"
            default: "Ended"
            }
        }
        public static let waitingForMessage = "Waiting for your next message here"
        /// `GROUPS`: what Pebble may do in it.
        public static func abilityName(_ key: String) -> String {
            switch key {
            case "look": "Look around"
            case "fill": "Fill in"
            case "press": "Press buttons"
            default: key
            }
        }
        public static func abilityNote(_ key: String) -> String? {
            switch key {
            case "look": "Move focus, scroll, and open or close sections. Nothing changes."
            case "fill": "Choose options, tick boxes and type text, never into a password, code or card field."
            case "press": "Anything that could submit, send, buy or delete waits for your approval in Pebble first."
            default: nil
            }
        }
        /// "Can look around, fill in"; "Can do nothing".
        public static func abilities(_ keys: [String]) -> String {
            keys.isEmpty ? "Can do nothing" : "Can " + keys.map { abilityName($0).lowercased() }.joined(separator: ", ")
        }
        /// " · Ends in about 3 minutes" after the state, or " · Time is up".
        public static func remaining(minutes: Int) -> String {
            minutes > 0 ? " · Ends in about " + (minutes == 1 ? "1 minute" : "\(minutes) minutes") : " · Time is up"
        }
        /// `REASONS`: why Pebble stopped and handed it over.
        public static func reason(_ key: String) -> String? {
            switch key {
            case "secure_field": "a password, code or card field"
            case "two_factor": "a verification code"
            case "captcha": "a check that you are a person"
            case "login_form": "a sign-in form"
            case "cross_origin": "a site you did not allow"
            case "paused": "you paused Pebble in Chrome"
            default: nil
            }
        }
        /// "Pebble stopped at a sign-in form." or "Pebble handed this window to you."
        public static func turn(reasons: [String], tab: Bool) -> String {
            let found = reasons.compactMap(reason)
            return found.isEmpty
                ? "Pebble handed this \(tab ? "tab" : "window") to you."
                : "Pebble stopped at " + found.joined(separator: ", ") + "."
        }
        public static func finishYourself(tab: Bool) -> String {
            "Finish it yourself in the \(tab ? "tab" : "window"). Pebble doesn't look at it while it's your turn and never sees what you type."
        }
        public static func uncertain(tab: Bool) -> String {
            "The last step has an uncertain outcome, so Pebble paused. Check the \(tab ? "tab" : "window") yourself; nothing is retried."
        }
        public static let pressDone = "Press Done when you've finished."
        public static let pressDoneUncertain = "Press Done when it looks right."
        public static let done = "Done"
        public static let endAccess = "End Access"
        public static func ended(tab: Bool) -> String {
            "Access ended. Pebble can no longer use this \(tab ? "tab" : "window")."
        }
        public static func finished(tab: Bool) -> String {
            "Done. Pebble looks at the \(tab ? "tab" : "window") again before it does anything else."
        }
    }

    // MARK: - Your Mac's screen (claude-w's C3, `remote.screenshot`)

    nonisolated public enum Screenshot {
        public static let title = AppCopy.MacScreen.title
        public static let take = "Take Screenshot"
        public static let takeAgain = AppCopy.MacScreen.refresh
        public static let taking = "Taking a screenshot"
        public static let note =
            "Takes a picture of your Mac's screen now. Your Mac keeps no copy and shows a notice each time; this iPhone keeps it only if you share it."
        public static let stealthNote = "While Stealth Lockdown is on, Pebble's own windows stay out of the picture."
        /// Displays are numbered from 1 for the person; `index` counts from 0, as the bridge does.
        public static func display(_ index: Int) -> String { AppCopy.MacScreen.display(index + 1) }
        public static let displays = AppCopy.MacScreen.displayPicker
        public static func taken(_ date: Date) -> String { "Taken \(date.formatted(date: .omitted, time: .standard))" }
        public static let share = "Share"
        public static let zoomHint = "Pinch to zoom, double-tap to fit"
        /// VoiceOver label for the picture.
        public static func imageLabel(display: Int, taken: Date) -> String {
            "\(AppCopy.MacScreen.imageLabel), \(self.display(display)), \(self.taken(taken).lowercased())"
        }
    }
}

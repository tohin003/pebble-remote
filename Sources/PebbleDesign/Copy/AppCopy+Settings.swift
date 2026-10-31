import Foundation
import PebbleProtocol

// Lane S (2026-10-31): the words of the Settings controls that were "On your Mac" rows. Pebble's sentences are word for
// word from its Settings (read-only Pebble checkout; `SettingsControlsParityTests` finds each one there); buttons and
// titles take Apple's title style, and the Mac's sentence-case label is kept beside a button where the two differ.
// Where a Mac sentence names a place on the Mac, or reads badly on a phone, the phone's version changes only that, and
// says why.
extension AppCopy {
    // MARK: - Settings › Memory: learning candidates, a memory added by hand, Forget all (AdvancedSettings.vue)

    nonisolated public enum Learning {
        /// The Mac's list is labelled "Learning candidates" (its aria-label); here it is a row and a screen's title.
        public static let title = "Learning Candidates"
        public static let note = SettingsCopy.Memory.candidatesNote
        /// The row's value: how many wait, or "None".
        public static func count(_ count: Int) -> String { count == 0 ? "None" : "\(count)" }
        /// The phone's line when nothing waits (the Mac shows no row then).
        public static let noneWaiting = "No learning candidates."

        /// `CANDIDATE_STATES`; any other state reads "Waiting", as on the Mac.
        public static func state(_ status: String) -> String {
            switch status {
            case "pending": "Waiting for evidence"
            case "conflict": "Disagrees with a saved memory"
            case "unsupported": "Not saved"
            default: "Waiting"
            }
        }

        /// `CANDIDATE_REASONS`, Pebble's reason codes in words.
        public static func reason(_ code: String) -> String? {
            switch code {
            case "run_consent_disabled": "memory was off when that task started"
            case "file_permission_unavailable": "reading project files is off in Permissions"
            case "durable_human_preference_required": "it was not something you said you prefer"
            case "exact_source_quote_required": "the text is not an exact quote of its source"
            case "quote_not_observed": "Pebble did not see this text in its source"
            case "current_disk_witness_required": "the file changed since Pebble read it"
            case "source_changed": "the source changed since Pebble read it"
            case "fresh_temporal_receipt_required": "the time-sensitive source is no longer fresh"
            case "dated_source_required": "the source has no date"
            case "wait_for_settled_test_evidence": "waiting for the test run to finish"
            case "wait_for_settled_lesson_evidence": "waiting for the task to finish"
            case "completed_test_recipe_required": "a finished, passing test run is needed"
            case "successful_broker_test_required": "a passing test run is needed"
            case "new_test_evidence_required_after_failure": "a new passing run is needed after a failure"
            case "lesson_evidence_required": "no task result supports it"
            case "lesson_evidence_not_current": "the task results behind it changed"
            case "unsafe_lesson_text": "the text looked unsafe to keep"
            case "sensitive_or_oversized_evidence": "the evidence was sensitive or too large"
            case "contested_record": "it disagrees with another saved memory"
            default: nil
            }
        }

        /// A reason code Pebble's list doesn't name.
        public static let unknownReason = "Pebble could not confirm it from its evidence"

        /// `candidateText`: "Waiting for evidence: waiting for the test run to finish".
        public static func line(status: String, reason: String?) -> String {
            guard let reason else { return state(status) }
            return state(status) + ": " + (self.reason(reason) ?? unknownReason)
        }

        /// What the Mac shows for a candidate without words (a test recipe).
        public static let testRecipe = "A test recipe Pebble saw pass"
        public static let useValue = "Use This Value"
        public static let useValueOnMac = "Use this value"
        public static let keepCurrent = "Keep Current"
        public static let keepCurrentOnMac = "Keep current"
        public static let checkNow = "Check Waiting Memories Now"
        public static let checkNowOnMac = "Check waiting memories now"
        /// Pebble's title on its buttons while a task runs.
        public static let idleOnly = "Available when the task is idle"

        // Adding a memory by hand ("Add {layer}", "Recall scope", "Expires at", "Save memory")

        /// The phone's sheet title (as "New Schedule"); the field's header keeps the Mac's "Add {layer}".
        public static let newMemory = "New Memory"
        /// The Mac's label: "Add your preferences", "Add facts & knowledge".
        public static func addLayer(_ name: String) -> String { "Add " + name.lowercased() }
        public static let placeholder = "Something useful to recall later…"
        public static let recallScope = "Recall scope"
        public static let personal = "Personal · all conversations"
        /// The Mac's second choice. Settings on the phone belong to no conversation, so the phone names the project
        /// instead (`project(_:)`).
        public static let currentProjectOnMac = "Current conversation's connected project"
        public static func project(_ name: String) -> String { "Project · \(name)" }
        public static let expiresAt = "Expires at"
        public static let save = "Save Memory"
        public static let saveOnMac = "Save memory"
        /// Under the field once it holds Pebble's limit (the Mac's field stops there too).
        public static let atLimit = "Pebble keeps up to 4,000 characters in one memory."

        // Forget all memories

        public static let forgetAll = "Forget All Memories"
        public static let forgetAllOnMac = "Forget all memories"
        /// The Mac's confirmation, split where it asks: the question, then what it means.
        public static let forgetAllQuestion = "Delete all saved memories and task checkpoints?"
        public static let forgetAllNote =
            "Conversations stay available. Pebble won't learn these again from the same conversations, and an archive you exported earlier won't restore them."
        public static let forgetPermanently = "Forget Permanently"
        public static let forgetPermanentlyOnMac = "Forget permanently"
        public static let keepThem = "Keep Them"
        public static let keepThemOnMac = "Keep them"
        /// What Forget all did, said where it was asked (Phase 45 F016).
        public static let forgotAll =
            "Forgot all saved memories and task checkpoints. Your conversations are still here."
    }

    // MARK: - Settings › Skills & connectors (AdvancedSettings.vue, tab "extensions", "SKILLS AND CONNECTORS")

    nonisolated public enum Skills {
        /// "SKILLS AND CONNECTORS", in title style: the row and the screen.
        public static let title = SettingsTab.skillsAndConnectors
        /// Pebble's note above its list.
        public static let note =
            "Skills teach Pebble a way of doing a task, such as your team's release checklist. Connectors plug Pebble into other apps and services, such as GitHub or Notion, through the MCP standard. Everything you add starts switched off until you have looked at it, and nothing here can give Pebble more access than Permissions allow. Hooks (advanced) are small rules that run at task steps in a sealed-off Python worker; they need terminal permission."
        /// The note's third sentence, under Enable and Disable.
        public static let startsOff =
            "Everything you add starts switched off until you have looked at it, and nothing here can give Pebble more access than Permissions allow."
        /// The phone's line when Pebble lists none.
        public static let empty = "No skills or connectors yet."

        /// `extensionNouns`; another kind shows as Pebble names it.
        public static func noun(_ kind: String) -> String {
            switch kind {
            case "skill": "Skill"
            case "hook": "Hook"
            case "plugin": "Connector"
            default: kind
            }
        }

        public static let enabled = "Enabled"
        public static let disabled = "Disabled"
        /// A card's line: "Connector · Disabled · search_issues, get_issue".
        public static func line(kind: String, enabled: Bool, capabilities: [String]) -> String {
            noun(kind) + " \u{00B7} " + (enabled ? self.enabled : disabled)
                + (capabilities.isEmpty ? "" : " \u{00B7} " + capabilities.joined(separator: ", "))
        }

        /// The Review's heading: "Review skill", "Review connector", "Review hook", or "Review extension".
        public static func review(_ kind: String) -> String {
            "Review " + (["skill", "hook", "plugin"].contains(kind) ? noun(kind) : "extension").lowercased()
        }

        public static let enable = "Enable"
        public static let disable = "Disable"

        // A connector's Review

        public static func destination(transport: String, era: String, address: String) -> String {
            "\(transport) \u{00B7} \(era) protocol \u{00B7} \(address). Calls require native review."
        }
        public static func reviewedVersion(_ digest: String, protocolVersion version: String?) -> String {
            "Reviewed version \(digest) \u{00B7} protocol \(version ?? ""). The server is checked again before every call."
        }
        /// The Mac's access line names the grant's state, which only the Mac reads (`connector_metadata` is a sign-in
        /// method the phone can't call). The phone knows whether a grant is configured: none is the Mac's
        /// "disconnected", word for word; one reads "granted", and its state stays on the Mac.
        public static func access(grantConfigured: Bool) -> String {
            accessOnMac(grantConfigured ? "granted" : "disconnected")
        }
        public static func accessOnMac(_ state: String) -> String {
            "Connector access: \(state). Credential values are withheld."
        }
        public static func packageChecksum(_ digest: String) -> String {
            "Package checksum \(digest) \u{00B7} publisher unverified."
        }

        // A skill's Review

        public static func snapshot(_ digest: String, name: String) -> String {
            "Snapshot \(digest). Use /skill \"\(name)\" followed by your task."
        }
        /// A file's line under its path: "1,204 bytes · 9f2c…".
        public static func fileLine(bytes: Int?, sha256: String) -> String {
            "\(bytes.map(String.init) ?? "?") bytes \u{00B7} \(sha256)"
        }
        /// The Mac's "View text", said to VoiceOver on a readable file's row (the row opens its text).
        public static let viewText = "View Text"
        public static let viewTextOnMac = "View text"
        /// Above a file's text.
        public static func textNote(_ path: String) -> String {
            "\(path) \u{00B7} imported snapshot; scripts are viewed as text."
        }
        public static let loadNextPage = "Load Next Page"
        public static let loadNextPageOnMac = "Load next page"

        // What stays on the Mac: Remove (SK-07), adding one, packages, and connector sign-in (SK-08), in one row.
        public static let onYourMac = "Remove, Add and Sign In"
        public static let onYourMacNote =
            "Removing or adding a skill or connector, connector packages and connector sign-in happen in Pebble\u{2019}s Settings on your Mac."
    }

    // MARK: - Settings › Data & storage (StorageSettings.vue)

    nonisolated public enum DataStorage {
        /// The Settings row that opens the screen (one row for the Mac's whole page, under its section).
        public static let manage = "Manage Data"
        /// The screen: the Mac's tab, in title style.
        public static let title = "Data & Storage"

        /// The Mac's disclosure, in title style.
        public static let recentChanges = "Recent Changes from Your Files"
        public static let recentChangesOnMac = "Recent changes from your files"
        public static let updateCopies = "Update Copies Now"
        public static let updateCopiesOnMac = "Update copies now"
        public static let upToDate = "Copies are up to date."
        /// While deletions in the Documents copies wait (the Mac's sentence names its button in its own case).
        public static func checking(_ count: Int) -> String {
            "Pebble is checking \(count) \(count == 1 ? "deletion" : "deletions") in your Documents copies. It acts once a deletion has lasted a minute, or at once when you choose Update copies now."
        }

        /// The Mac's "Recently deleted" block, where its two Delete all buttons are.
        public static let recentlyDeleted = "Recently deleted"
        public static let deleteAllNow = "Delete All Now\u{2026}"
        public static let deleteAllNowOnMac = "Delete all now\u{2026}"
        public static let deleteAllConversations = "Delete All Conversations\u{2026}"
        public static let deleteAllConversationsOnMac = "Delete all conversations\u{2026}"
        /// The safe answer to both questions.
        public static let keep = "Keep"

        /// "Delete all now…": the Mac's question, split where it asks.
        public static func purgeAllQuestion(_ count: Int) -> String {
            "Delete all \(conversations(count)) in Recently deleted for good?"
        }
        public static let purgeAllNote =
            "They cannot be restored. Copies made earlier in backups and the old folder stay until you remove them."
        public static let purgeAllButton = "Delete All for Good"
        public static let purgeAllButtonOnMac = "Delete all for good"

        /// "Delete all conversations…". The Mac says the conversations can be restored "here" (its Data & storage page
        /// lists Recently deleted); on the phone they are restored in Recently Deleted, so only the place changes.
        public static let trashAllQuestion = "Move every conversation to Recently deleted?"
        public static let trashAllNoteOnMac =
            "You can restore them here for 30 days. A conversation with a running task or an active schedule stays."
        public static let trashAllNote =
            "You can restore them in Recently Deleted for 30 days. A conversation with a running task or an active schedule stays."
        public static let trashAllButton = "Move All to Recently Deleted"
        public static let trashAllButtonOnMac = "Move all to Recently deleted"

        /// What each did, in the Mac's words.
        public static func moved(_ count: Int, kept: Int) -> String {
            let stays = kept == 1 ? "conversation stays" : "conversations stay"
            return "Moved \(conversations(count)) to Recently deleted."
                + (kept > 0 ? " \(kept) \(stays) because a task or schedule uses it." : "")
        }
        public static func purged(_ count: Int) -> String { "Deleted \(conversations(count)) for good." }

        static func conversations(_ count: Int) -> String {
            "\(count) \(count == 1 ? "conversation" : "conversations")"
        }

        /// What stays on the Mac: the folders, the copies' switch and place, sizes and deleting them, settings.json and
        /// PEBBLE.md, and the old sign-in copies (SD-13).
        public static let onYourMac = SettingsTab.storageRow
        public static let onYourMacNote =
            "Pebble\u{2019}s folder, its readable copies in Documents, the space it uses and old sign-in copies are in Pebble\u{2019}s Settings on your Mac."
    }

    // MARK: - Settings › Privacy & Stealth: usage telemetry (TelemetrySettings.vue)

    /// Pebble's words; where one says "this Mac", the phone says "your Mac" (only the place changes: the log is on the
    /// Mac, not on this iPhone).
    nonisolated public enum Telemetry {
        /// "Usage telemetry" (the Mac's heading), in title style.
        public static let title = "Usage Telemetry"
        public static let titleOnMac = "Usage telemetry"
        public static let on = "On"
        public static let off = "Off"
        /// Pebble's `plural(n, 'event')`.
        public static func events(_ count: Int) -> String { "\(count) event" + (count == 1 ? "" : "s") }
        /// The status line: "On since 31 Oct 2026 at 10:02 · 3 events kept · kept only on your Mac; …".
        public static func statusOn(since: String, events count: Int) -> String {
            on + " since \(since) \u{00B7} \(events(count)) kept" + keptOnYourMac
        }
        public static let statusOff = off + " \u{00B7} nothing is collected" + keptOnYourMac
        static let keptOnYourMac = " \u{00B7} kept only on your Mac; nothing is uploaded."
        public static let keptOnThisMac = " \u{00B7} kept only on this Mac; nothing is uploaded."
        /// When Pebble gives no time it was turned on.
        public static let unknownSince = "unknown"
        public static func limits(events: Int, kilobytes: Int, days: Int) -> String {
            "Limits: \(events) events or \(kilobytes) KB, for \(days) days; the oldest are removed first."
        }
        public static let whatEachEventHolds = "What Each Event Can Contain"
        public static let whatEachEventHoldsOnMac = "What each event can contain"
        public static func field(_ kind: String, _ names: [String]) -> String {
            kind + ": " + names.joined(separator: ", ")
        }
        /// The acknowledgement, a switch here (a checkbox on the Mac).
        public static let agree = "I have read this notice and want to turn telemetry on"
        public static let turnOn = "Turn On"
        public static let turnOnOnMac = "Turn on"
        public static func removed(dropped: Int, expired: Int, refused: Int) -> String {
            "Removed: \(dropped) over the limit, \(expired) expired, \(refused) refused."
        }
        public static func randomID(_ id: String) -> String { "Random ID \(id); it changes when you clear the log." }
        public static let turnOff = "Turn Off and Delete the Log"
        public static let turnOffOnMac = "Turn off and delete the log"
        /// What each did.
        public static let turnedOn = "Telemetry is on. It stays on your Mac until you save a copy."
        public static let turnedOnOnMac = "Telemetry is on. It stays on this Mac until you save a copy."
        public static let turnedOff = "Telemetry is off and its log was deleted."
        /// Save a copy… (the Mac's Save dialog) and Clear log stay on the Mac: one row.
        public static let onYourMac = "Save a Copy and Clear Log"
        public static let onYourMacNote =
            "Saving a copy of the log through the Mac\u{2019}s Save dialog, and clearing it, happen in Pebble\u{2019}s Settings on your Mac."
    }

    // MARK: - Settings › Permissions: Pebble's Shell (AdvancedSettings.vue, "PEBBLE'S SHELL")

    nonisolated public enum ShellAccess {
        /// "PEBBLE'S SHELL", in title style.
        public static let section = "Pebble\u{2019}s Shell"
        /// The phone's row: the list the Mac shows under the heading.
        public static let row = "Websites and Folders"
        public static let protectedPlaces = SettingsCopy.Permissions.protectedPlaces
        public static let website = "Website"
        public static let folder = "Folder Pebble may write in"
        public static let always = "always allowed"
        public static let untilQuit = "allowed until Pebble quits"
        /// A grant's line: "Website · always allowed".
        public static func line(website isSite: Bool, always isAlways: Bool) -> String {
            (isSite ? website : folder) + " \u{00B7} " + (isAlways ? always : untilQuit)
        }
        public static let remove = "Remove"
        /// VoiceOver's name for Remove on a row.
        public static func removeLabel(_ value: String) -> String { "Remove \(value)" }
        public static let empty =
            "Nothing is always allowed yet. When Pebble asks, \"Always allow\" adds a website or folder here."
        /// Under the list: Remove asks for Face ID (contract 3.6), and waits while a task runs, as the Mac's does.
        public static let removeNeedsFaceID = "Removing one asks for Face ID."
        public static let idleOnly = Learning.idleOnly
    }

    // MARK: - Settings › General: notification delivery (NotificationSettings.vue, "Delivery")

    nonisolated public enum Delivery {
        public static let section = "Delivery"
        /// `outboxLine`, then the banners held for quiet hours when there are any.
        public static func outbox(waiting: Int, shown: Int, notShown: Int, failed: Int, held: Int) -> String {
            "Waiting \(waiting) \u{00B7} Shown \(shown) \u{00B7} Not shown \(notShown) \u{00B7} Failed \(failed)"
                + (held > 0 ? " \u{00B7} Held for quiet hours \(held)" : "")
        }
        public static let quietNow = "Quiet hours are on now."
        /// `failureText`: Pebble's codes for a banner that couldn't be shown.
        public static func problem(_ code: String) -> String {
            let words =
                switch code {
                case "not_authorized": "macOS did not allow a notification."
                case "denied": "macOS declined a notification."
                case "unavailable": "The notification service was unavailable."
                case "no_acknowledgement": "The desktop shell did not confirm a notification."
                case "removal_unconfirmed": "The desktop shell did not confirm removing a notification."
                default: "A notification could not be shown."
                }
            return "Last problem: " + words
        }
        /// After the schedule's name: " · banners muted" or " · banners on".
        public static func state(muted: Bool) -> String { muted ? " \u{00B7} banners muted" : " \u{00B7} banners on" }
        public static let mute = "Mute"
        public static let unmute = "Unmute"
        /// VoiceOver's name for the button: "Mute banners for Weekly commit summary".
        public static func label(_ name: String, muted: Bool) -> String {
            (muted ? "Unmute banners for " : "Mute banners for ") + name
        }
        /// What a change did.
        public static func muted(_ name: String) -> String {
            "Banners for \u{201C}\(name)\u{201D} are muted. Its updates stay in the app."
        }
        public static func unmuted(_ name: String) -> String { "Banners for \u{201C}\(name)\u{201D} are back on." }
        public static let noSchedules = "No schedules yet."
    }

    // MARK: - Settings › Models: a model file's Rest model and Load now (AdvancedSettings.vue, tab "models")

    nonisolated public enum LocalModel {
        public static let rest = "Rest Model"
        public static let restOnMac = "Rest model"
        public static let load = "Load Now"
        public static let loadOnMac = "Load now"
        /// Pebble's title on its buttons while a task runs.
        public static let idleOnly = Learning.idleOnly
    }
}

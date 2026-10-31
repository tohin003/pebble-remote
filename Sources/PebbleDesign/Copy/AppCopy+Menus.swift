import Foundation
import PebbleProtocol

// Lane Z (2026-10-31, docs/lanes/Z-brief.md): the words of the long-press menus on Chats and in the transcript, the
// composer's "/" commands and Settings › Memory. Pebble's own sentences are kept word for word (App.vue,
// MessageActions.vue, slashCommands.ts, AdvancedSettings.vue, MemoryContests.vue); where one names a place that differs
// on the phone, the Mac's words stay beside the phone's variant, which changes only the place (docs/DESIGN.md §4).
extension AppCopy {
    // MARK: - A long press on a conversation in Chats (U-19; App.vue's sidebar row and its delete dialog)

    nonisolated public enum ChatMenu {
        public static let rename = Chats.rename
        public static let stop = Conversation.stop
        public static let delete = Deleted.delete
        /// The Mac's project rows: a new conversation in the row's project.
        public static func newConversation(in project: String) -> String { Sidebar.newConversation(in: project) }

        /// The Mac's delete dialog title (App.vue `deleteHeading`): the title clipped to 60 characters.
        public static func deleteTitle(_ title: String) -> String {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return "Delete this conversation?" }
            return "Delete \u{201C}\(name.count > 60 ? String(name.prefix(59)) + "\u{2026}" : name)\u{201D}?"
        }

        /// Pebble's sentence under the dialog's title, as the Mac says it.
        public static func deleteMessageOnMac(_ title: String) -> String {
            SettingsCopy.Conversations.moveConfirmOnMac(title)
        }

        /// The same sentence on the phone: deleting at once is Recently Deleted's "Delete for Good" here.
        public static func deleteMessage(_ title: String) -> String {
            "\u{201C}\(title)\u{201D} moves to Recently deleted, where you can restore it for 30 days. After that it is deleted with its messages, attachments and review history. To delete it at once, use \(Deleted.deleteForGood) in \(Deleted.title)."
        }

        /// The dialog's button (the Mac's "Move to Recently deleted", in the phone's title style).
        public static let moveToRecentlyDeleted = SettingsCopy.Conversations.moveButton

        /// The preview's last line when it is the person's own message.
        public static func fromYou(_ text: String) -> String { "You: \(text)" }
    }

    // MARK: - A long press on a message (MessageActions.vue; App.vue's editor and markers)

    nonisolated public enum MessageMenu {
        public static let copy = Conversation.copy
        /// What VoiceOver hears for Copy (MessageActions.vue's labels).
        public static let copyYourMessage = "Copy your message"
        public static let copyReply = "Copy Pebble\u{2019}s reply"
        /// A code block's Copy (Markdown.vue's "Copy code", in title style).
        public static let copyCode = "Copy Code"
        /// One code block among several, named by its first line.
        public static func codeBlock(_ firstLine: String) -> String { firstLine.isEmpty ? copyCode : firstLine }
        /// A link in the message, opened on this iPhone, never on the Mac (F13). Pebble's "Open link".
        public static let openLink = "Open Link"
        /// Edit: Pebble's button and its note (MessageActions.vue, App.vue's editor).
        public static let edit = "Edit"
        public static let editNote = "Sends a new message; this one stays as it was."
        /// Retry: Pebble's button, and its title after "Retry: " (MessageActions.vue).
        public static let retry = "Retry"
        public static let retryNote = "Ask the same question again as a new message; this reply stays."
        /// Why Retry can't run (App.vue `retryReason`).
        public static let retryWithoutAttachments =
            "Attachments aren't sent again; attach them to a new message to ask with them."
        /// The window's markers under a message that was edited or asked again (App.vue `markers`).
        public static let edited = "Edited \u{00B7} new version below"
        public static let askedAgain = "Earlier reply \u{00B7} asked again below"

        // The editor, as a sheet (App.vue's ".message-editor").
        public static let editTitle = "Edit Your Message"
        /// The field's label (Pebble's "Edited message").
        public static let editField = "Edited message"
        /// The sheet's button, short so the title fits; VoiceOver hears Pebble's "Send edited".
        public static let send = Conversation.send
        public static let sendEdited = "Send edited"
    }

    // MARK: - The composer's "/" commands (SlashMenu.vue, slashCommands.ts)

    nonisolated public enum Slash {
        /// What VoiceOver calls the list (SlashMenu.vue's label).
        public static let label = "Slash commands"
        /// A command as the list shows it.
        public static func command(_ name: String) -> String { "/\(name)" }
        /// Pebble refuses it while a task runs (slashCommands.ts IDLE_REASON).
        public static let idleOnly = "Available when the task is idle"
        public static let noMatch = "No matching command."
        /// The notes on /goal's words and /criteria add's --evidence (slashCommands.ts `argumentOptions`).
        public static let goalTitle = "Or type a \"title\" to start a goal"
        public static let evidence = "Met only by current results of finished steps"

        /// The note beside an argument word, where Pebble's window gives one.
        public static func note(command: String, option: String) -> String? {
            switch (command, option) {
            case ("goal", _): goalTitle
            case ("criteria", "--evidence"): evidence
            default: nil
            }
        }
    }

    // MARK: - Settings › Memory (AdvancedSettings.vue's memory tab, MemoryContests.vue)

    /// What Pebble remembers, in Pebble's words: each record in words and where it came from (never an origin code, a
    /// field name or "undefined"), and the contested memories as decisions.
    nonisolated public enum Memories {
        // The screens
        public static let layers = PebbleSettings.memoryLayers
        public static let layerSwitch = SettingsCopy.Memory.layerSwitch
        /// A layer's row: how many memories it holds, and "Off" when its learning and recall are off.
        public static func layerValue(count: Int?, isOn: Bool) -> String {
            switch (count, isOn) {
            case (let count?, true): "\(count)"
            case (let count?, false): "\(PebbleSettings.off) \u{00B7} \(count)"
            case (nil, true): ""
            case (nil, false): PebbleSettings.off
            }
        }
        /// The list's name (Pebble's "Saved memories").
        public static let saved = "Saved Memories"
        public static let searchPrompt = "Search this layer"
        public static let nothingSaved = SettingsCopy.Memory.nothingSaved
        public static func noMatch(_ query: String) -> String { "No memories in this layer match \u{201C}\(query)\u{201D}." }
        /// Pebble's "Load more", in title style.
        public static let loadMore = "Load More"
        public static let forget = SettingsCopy.Memory.forget
        public static let keep = SettingsCopy.Memory.keep
        public static let copy = Conversation.copy
        /// Why Forget waits (Pebble's title on the button while a task runs).
        public static let idleOnly = Slash.idleOnly
        /// The Forget question (Pebble's "Forget {text}?", its first 40 characters) and Pebble's note.
        public static func forgetTitle(_ words: String) -> String { "Forget \u{201C}\(clip(oneLine(words), 40))\u{201D}?" }
        public static let forgetNote = SettingsCopy.Memory.forgetNote
        /// VoiceOver's name for Forget on a record (AdvancedSettings.vue `forgetLabel`).
        public static func forgetLabel(_ words: String) -> String {
            let line = oneLine(words)
            return "Forget this memory: " + (line.isEmpty ? "untitled" : clip(line, 40))
        }

        // A record in words (AdvancedSettings.vue `memoryText`)

        /// A record's words: its text, or for a record Pebble keeps as data (a task's state, a past request and its
        /// result, a lesson, a quote, a weather reading, a test recipe) the sentence Pebble's Memory settings make of it.
        public static func text(kind: String, content: String, scope: String) -> String {
            guard let data = content.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                value.object != nil
            else { return content }
            if kind == "working" { return working(value) }
            if kind == "episodic", let line = episode(value, scope: scope) { return line }
            if kind == "temporal", !words(value["place"]).isEmpty { return weather(value) }
            if let quote = value["quote"]?.string {
                let source = words(value["path"]).isEmpty ? words(value["source"]) : words(value["path"])
                return "\u{201C}" + quote + "\u{201D}" + (source.isEmpty ? "" : "\nFrom " + source)
            }
            if kind == "procedural", let recipe = value["recipe"]?.string {
                let language = words(value["language"])
                return "Known test recipe: " + recipe + (language.isEmpty ? "" : " (" + language + ")")
                    + ". It never runs from memory; each run still follows your permissions."
            }
            return content
        }

        static func working(_ value: JSONValue) -> String {
            let goal = words(value["current_goal"])
            let phase = words(value["phase"])
            let actions = (value["actions"]?.array ?? []).filter { $0.object != nil }
            var lines = [goal.isEmpty ? "A task in progress" : "Current task: " + goal]
            if !phase.isEmpty { lines.append("State: " + phase.replacingOccurrences(of: "_", with: " ")) }
            if !actions.isEmpty {
                let said = actions.map { action in
                    let path = words(action["path"])
                    let status = words(action["status"])
                    let name = path.isEmpty ? (actionNouns[action["kind"]?.string ?? ""] ?? "Action") : path
                    let parts = [name, actionStates[action["status"]?.string ?? ""] ?? status].filter { !$0.isEmpty }
                    let exit = action["result"]?["exit_code"].flatMap(number).map { " \u{00B7} exit " + $0 } ?? ""
                    return parts.joined(separator: " \u{00B7} ") + exit
                }
                lines.append("Actions: " + said.joined(separator: "; "))
            }
            return lines.joined(separator: "\n")
        }

        static func episode(_ value: JSONValue, scope: String) -> String? {
            let place = scope.hasPrefix("chat:") ? "this conversation" : "this project"
            switch value["claim_class"]?.string ?? "" {
            case "observed_outcome", "host_lesson":
                let seen = words(value["observation"])
                return seen.isEmpty ? "A past result in " + place + "." : "Seen in " + place + ": " + seen
            case "model_lesson_unverified":
                let lesson = words(value["lesson"])
                return lesson.isEmpty
                    ? "A lesson suggested by the model (not verified)."
                    : "Lesson suggested by the model (not verified): " + lesson
            default:
                break
            }
            if value["user_request"] != nil || value["task_outcome"] != nil {
                let asked = words(value["user_request"])
                let outcome = value["task_outcome"]?.string ?? ""
                let result = outcomes[outcome] ?? words(value["task_outcome"]).replacingOccurrences(of: "_", with: " ")
                let actions = (value["broker_evidence"]?.array ?? []).filter { $0.object != nil }
                var lines = [
                    asked.isEmpty ? "An earlier request" : "Asked: " + asked,
                    "Result: " + (result.isEmpty ? "not recorded" : result),
                ]
                if !actions.isEmpty {
                    lines.append(actions.map { action in
                        let state = actionStates[action["status"]?.string ?? ""] ?? words(action["status"])
                        return (actionNouns[action["kind"]?.string ?? ""] ?? "Action") + " \u{00B7} "
                            + (state.isEmpty ? "unknown" : state)
                    }.joined(separator: "; "))
                }
                if let steps = stepWords(value["tool_steps"]) {
                    lines.append(steps)
                } else if actions.isEmpty {
                    lines.append("No file, command or app actions.")
                }
                return lines.joined(separator: "\n")
            }
            let seen = words(value["observation"])
            if !seen.isEmpty { return seen }
            let lesson = words(value["lesson"])
            return lesson.isEmpty ? nil : lesson
        }

        static func weather(_ value: JSONValue) -> String {
            let date = words(value["date"])
            let reading = (value["temperature_c"].flatMap(number) ?? "?") + " \u{00B0}C \u{00B7} forecast "
                + (value["forecast_low_c"].flatMap(number) ?? "?") + "\u{2013}"
                + (value["forecast_high_c"].flatMap(number) ?? "?") + " \u{00B0}C"
            var lines = [words(value["place"]) + (date.isEmpty ? "" : " \u{00B7} " + date), reading]
            if let retrieved = moment(value["retrieved"]) {
                lines.append("Retrieved " + retrieved.formatted(date: .abbreviated, time: .shortened))
            }
            return lines.joined(separator: "\n")
        }

        /// "Steps: 3 commands, 1 file written." (AdvancedSettings.vue `stepWords`).
        static func stepWords(_ value: JSONValue?) -> String? {
            guard let steps = value?.object else { return nil }
            let parts = stepNouns.compactMap { kind, nouns -> String? in
                guard let count = steps[kind]?.int, count > 0, steps[kind]?.double == Double(count) else { return nil }
                return "\(count) " + (count == 1 ? nouns.one : nouns.many)
            }
            return parts.isEmpty ? nil : "Steps: " + parts.joined(separator: ", ") + "."
        }

        // Where a record came from (AdvancedSettings.vue `memoryOrigin`, `memoryMeta`)

        public static func origin(_ origin: String, kind: String, evidenceClass: String?, id: String) -> String {
            if id == "pebble-md" { return "From PEBBLE.md" }
            switch origin {
            case "direct-user": return "You asked Pebble to remember this"
            case "user": return "Added in Settings"
            case "curated": return "Built into Pebble"
            case "imported": return "Imported from a memory archive"
            case "broker": return "Task state"
            case "conversation": return kind == "episodic" ? "Learned from a task" : "From a conversation"
            case "auto-learned":
                return evidenceClass.flatMap { learnedFrom[$0] }
                    ?? (kind == "procedural" ? "Learned from a test run" : "Learned from a task")
            default: return "Saved by Pebble"
            }
        }

        /// "Personal", "Conversation" or "Project".
        public static func scopeName(_ scope: String) -> String {
            scope == "global" ? "Personal" : scope.hasPrefix("chat:") ? "Conversation" : "Project"
        }

        /// The line above a record: where it came from, whose it is, its conversation, when, and what learning says.
        public static func meta(
            origin: String, scope: String, chatTitle: String?, updated: Date?, learningStatus: String?, expires: Date?
        ) -> String {
            [
                origin, scopeName(scope), chatTitle.map { $0.isEmpty ? "" : "From: " + $0 } ?? "",
                updated?.formatted(date: .abbreviated, time: .omitted) ?? "",
                learningStatus.flatMap { learningStates[$0] } ?? "",
                expires.map { "expires " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "",
            ].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }

        // Contested memories (MemoryContests.vue)

        public static let contested = "Contested Memories"
        public static let contestNote =
            "When two memories disagree, Pebble does not recall either as current until you decide. Keep this forgets the memories that disagree with it. Remove this forgets this one. Keep both forgets nothing. You confirm each choice first."
        public static let decideLater = "Decide after the current task finishes."
        public static let noneContested = "No memory is contested."
        /// A record's role in a contest.
        public static let contestedRecord = "Contested"
        public static let disagrees = "Disagrees with it"
        /// The three decisions (Pebble's "Keep this", "Remove this", "Keep both", in title style), by Pebble's names.
        public static func decision(_ decision: String) -> String {
            switch decision {
            case "keep": "Keep This"
            case "reject": "Remove This"
            default: "Keep Both"
            }
        }

        /// A layer's name, or "Memory" (MemoryContests.vue `kindName`).
        public static func kindName(_ kind: String) -> String {
            SettingsCopy.Memory.layerOrder.contains(kind) ? SettingsCopy.Memory.layerName(kind) : "Memory"
        }

        public static func topic(_ label: String?) -> String? {
            guard let label, !label.isEmpty else { return nil }
            return label == "model_lesson_unverified" ? "Unverified lesson from the model" : "Topic: " + label
        }

        /// A contest record's line: its layer, whose it is, where it came from and when.
        public static func details(kind: String, scope: String, origin: String, created: Date?) -> String {
            [
                kindName(kind), scope.isEmpty ? "" : scopeName(scope), origin,
                created?.formatted(date: .abbreviated, time: .shortened) ?? "",
            ].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }

        /// "Your preferences: Write documents in British spelling."
        public static func summary(kind: String, content: String) -> String { kindName(kind) + ": " + clip(content, 80) }

        /// The confirmation's question.
        public static func question(_ decision: String) -> String {
            switch decision {
            case "keep": "Keep this memory?"
            case "reject": "Remove this memory?"
            default: "Keep both?"
            }
        }

        /// The confirmation's words: the memory, then exactly what is forgotten, or that nothing is.
        /// `forgets` are the (kind, content) of the records the decision forgets; `counterparts` how many disagree.
        public static func confirmation(
            _ decision: String, summary: String, forgets: [(kind: String, content: String)], counterparts: Int
        ) -> String {
            var parts = [summary]
            if !forgets.isEmpty {
                parts.append(
                    decision == "reject"
                        ? "This forgets:"
                        : "This forgets " + memories(forgets.count)
                            + (forgets.count == 1 ? " that disagrees" : " that disagree") + " with it:")
                parts.append(forgets.map { "\u{2022} " + kindName($0.kind) + " \u{00B7} " + clip($0.content, 280) }
                    .joined(separator: "\n"))
                parts.append(
                    "Forgetting is permanent. A forgotten memory stays forgotten, and importing an archive cannot bring it back.")
            } else if decision == "keep_both" {
                parts.append(
                    "Nothing is forgotten. Pebble records that you accept this disagreement, so these versions are not contested again.")
            } else {
                parts.append("Nothing is forgotten.")
            }
            if decision == "reject" && counterparts > 0 { parts.append("The memories that disagree with it are kept.") }
            return parts.joined(separator: "\n\n")
        }

        /// The confirmation's button (MemoryContests.vue `confirmLabel`).
        public static func confirm(_ decision: String, forgetting: Int) -> String {
            switch decision {
            case "keep_both": "Keep both"
            case "reject": "Forget this memory"
            default: forgetting > 0 ? "Keep this and forget " + memories(forgetting) : "Keep this"
            }
        }

        /// What the decision did (MemoryContests.vue `outcome`); `forgotten` is nil when Pebble's answer didn't say.
        public static func outcome(_ decision: String, forgotten: Int?) -> String {
            let done =
                switch decision {
                case "keep": "Kept this memory."
                case "reject": "Removed this memory."
                default: "Kept both."
                }
            guard let forgotten else { return done }
            return done + (forgotten > 0
                ? " " + memories(forgotten) + (forgotten == 1 ? " was" : " were") + " forgotten."
                : " Nothing was forgotten.")
        }

        static func memories(_ count: Int) -> String { count == 1 ? "1 memory" : "\(count) memories" }

        // Pebble's tables (AdvancedSettings.vue)

        static let actionNouns: [String: String] = [
            "edit": "File edit", "tests": "Test run", "command": "Command", "app": "App launch", "git": "Git change",
            "plugin": "Connector call", "worktree": "Helper worktree", "install": "Install",
            "screen": "Window or tab action", "screen_grant": "Window allowed", "browser_grant": "Sites allowed",
            "screen_raise": "Window brought forward", "url": "Link opened", "app_action": "App action",
            "shell": "Shell command", "file": "File change",
        ]
        static let actionStates: [String: String] = [
            "applied": "done", "completed": "done", "rejected": "declined", "failed": "failed",
            "pending": "waiting for you", "running": "running", "awaiting_user_approval": "waiting for you",
            "superseded": "replaced", "cancelled": "stopped", "uncertain": "outcome unknown",
        ]
        static let outcomes: [String: String] = [
            "completed": "finished", "not_completed": "not completed",
            "needs_reconciliation": "not completed: an app step's result was uncertain", "failed": "failed",
            "stopped": "stopped", "cancelled": "stopped", "interrupted": "interrupted",
            "budget_exhausted": "ran out of time or steps", "verification_required": "held for a check",
            "paused": "paused",
        ]
        static let stepNouns: [(String, (one: String, many: String))] = [
            ("command", ("command", "commands")), ("test run", ("test run", "test runs")),
            ("file", ("file written", "files written")), ("app_step", ("step in an app window", "steps in app windows")),
            ("app_opened", ("app opened", "apps opened")), ("link", ("link opened", "links opened")),
            ("script", ("script", "scripts")), ("refused", ("step refused", "steps refused")),
        ]
        static let learnedFrom: [String: String] = [
            "human_preference": "Learned from what you said", "confirmed_human_quote": "Learned from what you said",
            "attributed_file_quote": "Learned from a file Pebble read",
            "attributed_web_quote": "Learned from a web page Pebble read", "weather_service": "From a weather lookup",
            "host_lesson": "Learned from repeated task results",
            "model_lesson_unverified": "Suggested by the model (not verified)",
        ]
        static let learningStates: [String: String] = [
            "contested": "disagrees with another saved memory; not used until you choose",
            "superseded": "replaced by a newer version",
        ]

        static func words(_ value: JSONValue?) -> String {
            value?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        /// A number as JavaScript prints it: 24, 24.5.
        static func number(_ value: JSONValue) -> String? {
            switch value {
            case .int(let whole): "\(whole)"
            case .double(let real): real.rounded() == real && abs(real) < 1e15 ? "\(Int(real))" : "\(real)"
            default: nil
            }
        }

        /// A time Pebble stored as Unix seconds or milliseconds, or as an ISO 8601 string.
        static func moment(_ value: JSONValue?) -> Date? {
            if let seconds = value?.double, seconds > 0 {
                return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds)
            }
            guard let text = value?.string else { return nil }
            return try? Date(text, strategy: .iso8601)
        }

        static func oneLine(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        static func clip(_ text: String, _ limit: Int) -> String {
            text.count > limit ? String(text.prefix(limit)) + "\u{2026}" : text
        }
    }
}

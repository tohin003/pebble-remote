import Foundation
import Testing

@testable import PebbleDesign

// Lane Z's words: the long-press menus, the "/" commands and Settings › Memory. Pebble's own sentences are compared with
// Pebble's sources; the phone's variants, which change only a place, are checked here.

extension PebbleParityTests {
    /// The delete dialog of a long press on a conversation says what the Mac's delete dialog says (App.vue).
    @Test func theChatMenusDeleteDialogIsTheMacs() throws {
        let app = Self.collapse(try Self.read("src/App.vue"))
        #expect(app.contains(#"return title ? `Delete “${title.length > 60 ? title.slice(0, 59) + "…" : title}”?` : "Delete this conversation?";"#))
        #expect(app.contains(Self.collapse(
            "“{{ deleteTarget?.title }}” moves to Recently deleted, where you can restore it for 30 days. After that it is deleted with its messages, attachments and review history. To delete it at once, use Delete now in Settings → Data &amp; storage.")))
        #expect(AppCopy.ChatMenu.deleteMessageOnMac("T") ==
            "“T” moves to Recently deleted, where you can restore it for 30 days. After that it is deleted with its messages, attachments and review history. To delete it at once, use Delete now in Settings → Data & storage.")
        #expect(app.contains("Move to Recently deleted"))
    }
}

struct MenuCopyTests {
    @Test func theDeleteTitleClipsAsTheMacDoes() {
        #expect(AppCopy.ChatMenu.deleteTitle("Weather") == "Delete \u{201C}Weather\u{201D}?")
        #expect(AppCopy.ChatMenu.deleteTitle("  ") == "Delete this conversation?")
        let long = String(repeating: "a", count: 61)
        #expect(AppCopy.ChatMenu.deleteTitle(long) == "Delete \u{201C}" + String(repeating: "a", count: 59) + "\u{2026}\u{201D}?")
        let sixty = String(repeating: "b", count: 60)
        #expect(AppCopy.ChatMenu.deleteTitle(sixty) == "Delete \u{201C}\(sixty)\u{201D}?")
    }

    @Test func thePhoneSaysWhereDeleteForGoodIsHere() {
        let mac = AppCopy.ChatMenu.deleteMessageOnMac("T")
        let phone = AppCopy.ChatMenu.deleteMessage("T")
        let place = "use Delete now in Settings → Data & storage."
        #expect(mac.hasSuffix(place))
        #expect(phone == mac.replacingOccurrences(of: place, with: "use Delete for Good in Recently Deleted."))
        #expect(AppCopy.ChatMenu.moveToRecentlyDeleted == "Move to Recently Deleted")
        #expect(AppCopy.ChatMenu.fromYou("Run the tests") == "You: Run the tests")
    }
}

/// Lane Z, item 2: what a message's menu finds in it.
struct MessageMenuContentTests {
    @Test func codeBlocksAreFoundInOrderAndEmptyOnesLeftOut() {
        let reply = "First:\n```sh\nnpm test\n```\nThen:\n```\n\n```\n~~~\nnpm run build\nnpm run lint\n~~~"
        #expect(MessageMenu.codeBlocks(in: reply) == ["npm test", "npm run build\nnpm run lint"])
        #expect(MessageMenu.codeBlocks(in: "No code here.").isEmpty)
    }

    @Test func linksAreTheMarkdownLinksThenTheAddressesWrittenOut() throws {
        let text = "Read [the guide](https://example.com/guide) and https://docs.example.org/a b, or mail me@example.com."
        let links = MessageMenu.links(in: text)
        #expect(links == [try #require(URL(string: "https://example.com/guide")), try #require(URL(string: "https://docs.example.org/a"))])
    }

    @Test func aLinkIsListedOnceAndNeverFromCode() {
        let text = "[a](https://example.com/x) https://example.com/x\n```\nhttps://example.com/code\n```"
        #expect(MessageMenu.links(in: text).map(\.absoluteString) == ["https://example.com/x"])
    }

    @Test func onlyWebLinksWithAHostAreKept() {
        let text = "[pair](pebble-remote://pair?k=1) [call](tel:123) [file](file:///etc/hosts) [web](http://example.com)"
        #expect(MessageMenu.links(in: text).map(\.absoluteString) == ["http://example.com"])
    }

    @Test func aMenuListsAtMostSixOfEach() {
        let many = (1...9).map { "https://example.com/\($0)" }.joined(separator: " ")
        #expect(MessageMenu.links(in: many).count == MessageMenu.most)
    }

    @Test func menuItemsAreNamedShortly() throws {
        #expect(MessageMenu.firstLine("  let x = 1\nlet y = 2") == "let x = 1")
        #expect(MessageMenu.firstLine(String(repeating: "x", count: 50)).count == 40)
        #expect(MessageMenu.linkName(try #require(URL(string: "https://www.example.com/guide"))) == "example.com/guide")
        #expect(MessageMenu.linkName(try #require(URL(string: "https://example.com/"))) == "example.com")
        #expect(AppCopy.MessageMenu.codeBlock("") == AppCopy.MessageMenu.copyCode)
    }
}

extension PebbleParityTests {
    /// The message actions' words are Pebble's (MessageActions.vue, App.vue's editor, markers and Retry's reason).
    @Test func theMessageMenusWordsArePebbles() throws {
        let actions = Self.collapse(try Self.read("src/components/MessageActions.vue"))
        for text in [
            "'Copy your message'", "'Copy Pebble’s reply'", "aria-label=\"Edit your message\"", "Retry: ask again as a new message",
            "Retry: ask the same question again as a new message; this reply stays",
        ] {
            #expect(actions.contains(text), "MessageActions.vue: \(text)")
        }
        #expect(AppCopy.MessageMenu.copyYourMessage == "Copy your message")
        #expect(AppCopy.MessageMenu.copyReply == "Copy Pebble’s reply")
        #expect("Retry: " + AppCopy.MessageMenu.retryNote.prefix(1).lowercased() + AppCopy.MessageMenu.retryNote.dropFirst()
            == "Retry: ask the same question again as a new message; this reply stays.")
        let app = Self.collapse(try Self.read("src/App.vue"))
        for text in [
            AppCopy.MessageMenu.editNote, AppCopy.MessageMenu.retryWithoutAttachments, AppCopy.MessageMenu.edited,
            AppCopy.MessageMenu.askedAgain, AppCopy.MessageMenu.editField, AppCopy.MessageMenu.sendEdited,
        ] {
            #expect(app.contains(text), "App.vue: \(text)")
        }
        let markdown = try Self.read("src/components/Markdown.vue")
        #expect(markdown.contains("aria-label=\"Copy code\""))
    }
}

extension PebbleParityTests {
    /// The "/" list's words are Pebble's window's (SlashMenu.vue, slashCommands.ts).
    @Test func theSlashListsWordsArePebbles() throws {
        let menu = try Self.read("src/components/SlashMenu.vue")
        #expect(menu.contains("aria-label=\"\(AppCopy.Slash.label)\""))
        #expect(menu.contains(AppCopy.Slash.noMatch))
        let commands = try Self.read("src/slashCommands.ts")
        #expect(commands.contains("export const IDLE_REASON = \"\(AppCopy.Slash.idleOnly)\";"))
        #expect(commands.contains("'\(AppCopy.Slash.goalTitle)'"))
        #expect(commands.contains("\"\(AppCopy.Slash.evidence)\""))
        #expect(commands.contains("export const IDLE_ONLY: ReadonlySet<string> = new Set([\"compact\", \"handoff\", \"skill\"]);"))
    }
}

/// Lane Z, item 4: a memory in words, as Pebble's Memory settings say it (AdvancedSettings.vue `memoryText`,
/// `memoryOrigin`, `memoryMeta`; MemoryContests.vue).
struct MemoryWordsTests {
    typealias M = AppCopy.Memories

    @Test func aTaskCheckpointSaysTheTaskItsStateAndItsActions() {
        let checkpoint = #"{"current_goal":"Fix the login loop","phase":"running_tests","actions":[{"kind":"edit","path":"src/session.ts","status":"applied"},{"kind":"tests","status":"failed","result":{"exit_code":1}},"junk"]}"#
        #expect(M.text(kind: "working", content: checkpoint, scope: "chat:c1") == """
            Current task: Fix the login loop
            State: running tests
            Actions: src/session.ts \u{00B7} done; Test run \u{00B7} failed \u{00B7} exit 1
            """)
        #expect(M.text(kind: "working", content: "{}", scope: "chat:c1") == "A task in progress")
    }

    @Test func aPastRequestSaysWhatWasAskedAndHowItEnded() {
        let episode = #"{"user_request":"Summarize the commits.","task_outcome":"completed","tool_steps":{"command":2,"file":1}}"#
        #expect(M.text(kind: "episodic", content: episode, scope: "/Users/me/app") == """
            Asked: Summarize the commits.
            Result: finished
            Steps: 2 commands, 1 file written.
            """)
        let bare = #"{"task_outcome":"needs_reconciliation"}"#
        #expect(M.text(kind: "episodic", content: bare, scope: "chat:c1") == """
            An earlier request
            Result: not completed: an app step's result was uncertain
            No file, command or app actions.
            """)
        let seen = #"{"claim_class":"observed_outcome","observation":"npm test passes."}"#
        #expect(M.text(kind: "episodic", content: seen, scope: "chat:c1") == "Seen in this conversation: npm test passes.")
        let lesson = #"{"claim_class":"model_lesson_unverified","lesson":"Run lint first."}"#
        #expect(M.text(kind: "episodic", content: lesson, scope: "/p") == "Lesson suggested by the model (not verified): Run lint first.")
    }

    @Test func weatherQuotesAndRecipesReadAsPebbleWritesThem() {
        let weather = #"{"place":"Lisbon","date":"Saturday","temperature_c":24,"forecast_low_c":17.5,"forecast_high_c":25}"#
        #expect(M.text(kind: "temporal", content: weather, scope: "global") == "Lisbon \u{00B7} Saturday\n24 \u{00B0}C \u{00B7} forecast 17.5\u{2013}25 \u{00B0}C")
        let quote = #"{"quote":"Supports iOS 26.","path":"README.md"}"#
        #expect(M.text(kind: "semantic", content: quote, scope: "/p") == "\u{201C}Supports iOS 26.\u{201D}\nFrom README.md")
        let recipe = #"{"recipe":"npm test","language":"JavaScript"}"#
        #expect(M.text(kind: "procedural", content: recipe, scope: "/p") == "Known test recipe: npm test (JavaScript). It never runs from memory; each run still follows your permissions.")
        #expect(M.text(kind: "profile", content: "Prefers short replies.", scope: "global") == "Prefers short replies.")
        #expect(M.text(kind: "profile", content: "[1, 2]", scope: "global") == "[1, 2]")
    }

    @Test func whereAMemoryCameFromIsInWordsNeverACode() {
        #expect(M.origin("direct-user", kind: "profile", evidenceClass: nil, id: "m") == "You asked Pebble to remember this")
        #expect(M.origin("conversation", kind: "episodic", evidenceClass: nil, id: "m") == "Learned from a task")
        #expect(M.origin("conversation", kind: "semantic", evidenceClass: nil, id: "m") == "From a conversation")
        #expect(M.origin("auto-learned", kind: "semantic", evidenceClass: "attributed_file_quote", id: "m") == "Learned from a file Pebble read")
        #expect(M.origin("auto-learned", kind: "procedural", evidenceClass: nil, id: "m") == "Learned from a test run")
        #expect(M.origin("weird", kind: "semantic", evidenceClass: nil, id: "m") == "Saved by Pebble")
        #expect(M.origin("user", kind: "semantic", evidenceClass: nil, id: "pebble-md") == "From PEBBLE.md")
        let meta = M.meta(
            origin: "Added in Settings", scope: "chat:c1", chatTitle: "Weather", updated: nil, learningStatus: "contested",
            expires: nil)
        #expect(meta == "Added in Settings \u{00B7} Conversation \u{00B7} From: Weather \u{00B7} disagrees with another saved memory; not used until you choose")
        #expect(M.scopeName("global") == "Personal" && M.scopeName("/Users/me/app") == "Project")
    }

    @Test func aContestsConfirmationNamesWhatIsForgotten() {
        let summary = M.summary(kind: "profile", content: "Write in British spelling.")
        #expect(summary == "Your preferences: Write in British spelling.")
        let keep = M.confirmation("keep", summary: summary, forgets: [(kind: "profile", content: "Write in American spelling.")], counterparts: 1)
        #expect(keep == """
            Your preferences: Write in British spelling.

            This forgets 1 memory that disagrees with it:

            \u{2022} Your preferences \u{00B7} Write in American spelling.

            Forgetting is permanent. A forgotten memory stays forgotten, and importing an archive cannot bring it back.
            """)
        let reject = M.confirmation("reject", summary: summary, forgets: [(kind: "profile", content: "Write in British spelling.")], counterparts: 1)
        #expect(reject.contains("This forgets:") && reject.hasSuffix("The memories that disagree with it are kept."))
        #expect(M.confirmation("keep_both", summary: summary, forgets: [], counterparts: 1).hasSuffix("so these versions are not contested again."))
        #expect(M.confirm("keep", forgetting: 2) == "Keep this and forget 2 memories")
        #expect(M.confirm("keep", forgetting: 0) == "Keep this")
        #expect(M.confirm("reject", forgetting: 1) == "Forget this memory")
        #expect(M.outcome("keep", forgotten: 1) == "Kept this memory. 1 memory was forgotten.")
        #expect(M.outcome("keep_both", forgotten: 0) == "Kept both. Nothing was forgotten.")
        #expect(M.outcome("reject", forgotten: nil) == "Removed this memory.")
    }

    @Test func aLayerRowSaysHowManyAndWhetherItIsOff() {
        #expect(M.layerValue(count: 12, isOn: true) == "12")
        #expect(M.layerValue(count: 3, isOn: false) == "Off \u{00B7} 3")
        #expect(M.layerValue(count: nil, isOn: false) == "Off")
        #expect(M.forgetTitle("Prefers   short\nreplies with the exact commands to run every time") == "Forget \u{201C}Prefers short replies with the exact com\u{2026}\u{201D}?")
    }
}

extension PebbleParityTests {
    /// Settings › Memory's words are Pebble's (AdvancedSettings.vue, MemoryContests.vue).
    @Test func theMemoryWordsArePebbles() throws {
        let settings = Self.collapse(try Self.read("src/components/AdvancedSettings.vue"))
        for text in [
            "Search this layer", "No memories in this layer match “", "Load more", "Available when the task is idle",
            "Forget this memory: ", "Current task: ", "A task in progress", "Seen in ", "A past result in ",
            "Lesson suggested by the model (not verified): ", "An earlier request", "No file, command or app actions.",
            "Known test recipe: ", ". It never runs from memory; each run still follows your permissions.",
            "You asked Pebble to remember this", "Added in Settings", "Built into Pebble", "Imported from a memory archive",
            "Task state", "Learned from a task", "From a conversation", "Learned from a test run", "Saved by Pebble",
            "From PEBBLE.md", "disagrees with another saved memory; not used until you choose", "replaced by a newer version",
            "Learned from what you said", "Learned from a file Pebble read", "From a weather lookup",
            "Learned from repeated task results", "Suggested by the model (not verified)",
            "not completed: an app step's result was uncertain", "ran out of time or steps", "held for a check",
            "Window or tab action", "Window brought forward", "steps in app windows", "files written",
        ] {
            #expect(settings.contains(text), "AdvancedSettings.vue: \(text)")
        }
        let contests = Self.collapse(try Self.read("src/components/MemoryContests.vue"))
        for text in [
            AppCopy.Memories.contestNote, AppCopy.Memories.decideLater, AppCopy.Memories.noneContested,
            "'Keep this memory?'", "'Remove this memory?'", "'Keep both?'", "'Kept this memory.'", "'Removed this memory.'",
            "'Kept both.'", "'Keep this and forget '", "'Forget this memory'", "'Unverified lesson from the model'",
            "Forgetting is permanent. A forgotten memory stays forgotten, and importing an archive cannot bring it back.",
            "Nothing is forgotten. Pebble records that you accept this disagreement, so these versions are not contested again.",
            "The memories that disagree with it are kept.", "'Disagrees with it'", "'Contested'", ">Keep this<",
            ">Remove this<", ">Keep both<", "This forgets:",
        ] {
            #expect(contests.contains(text), "MemoryContests.vue: \(text)")
        }
    }
}

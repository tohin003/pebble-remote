import Foundation
import Testing

@testable import PebbleProtocol

// Pebble's vocabulary on the phone: tool classes (activity_kinds.py), run states (statusWords.ts RUN_STATUS), simple
// cards (app.py SIMPLE_CARDS) and the card words (App.vue).

@Test func everyToolOfPebblesTableHasItsClass() {
    // activity_kinds._CLASSES as of Pebble 1.9.28: 88 tools in 9 classes, each named once.
    let all = StatusKey.toolClasses.flatMap(\.tools)
    #expect(all.count == 88)
    #expect(Set(all).count == all.count)
    #expect(StatusKey.toolClasses.map(\.key) == [.reading, .searching, .editing, .testing, .running, .delegating, .viewing, .thinking, .working])
    #expect(StatusKey.forTool("Read") == .reading)
    #expect(StatusKey.forTool("Grep") == .searching)
    #expect(StatusKey.forTool("Edit") == .editing)
    #expect(StatusKey.forTool("RunTests") == .testing)
    #expect(StatusKey.forTool("Shell") == .running)
    #expect(StatusKey.forTool("SpawnAgent") == .delegating)
    #expect(StatusKey.forTool("UIRender") == .viewing)
    #expect(StatusKey.forTool("AskUserQuestion") == .thinking)
    #expect(StatusKey.forTool("BrowserRequest") == .working)
    // Anything unknown, or invented by a model, is plain working; a name never borrows a meaning.
    #expect(StatusKey.forTool("Approve") == .working)
    #expect(StatusKey.forTool(nil) == .working)
}

@Test func classifyFollowsActivityKinds() {
    #expect(StatusKey.classify(tool: "Read", kind: "working") == .reading)
    #expect(StatusKey.classify(tool: nil, kind: "working") == .thinking)
    #expect(StatusKey.classify(tool: "", kind: "working") == .thinking)
    #expect(StatusKey.classify(tool: "Read", kind: "done") == nil)
    #expect(StatusKey.classify(tool: "Shell", kind: "blocked") == nil)
    #expect(StatusKey.allCases.filter(\.isToolClass) == [.reading, .searching, .editing, .testing, .running, .delegating, .viewing, .working])
}

@Test func runStatesMatchPebblesRunStatus() {
    // statusWords.ts RUN_STATUS, word for word.
    let pebble: [String: String] = [
        "retry_wait": "reconnecting", "waiting_input": "question", "waiting_approval": "review",
        "budget_exhausted": "blocked", "verification_required": "blocked", "needs_reconciliation": "uncertain",
        "paused": "paused", "failed": "error",
    ]
    for state in RunState.pebbleStates {
        #expect(state.statusKey?.rawValue == pebble[state.rawValue], "\(state)")
    }
    // Compared as sets: a set's order is not fixed.
    let live: Set<RunState> = Set(RunState.pebbleStates.filter(\.isLive))
    let waiting: Set<RunState> = Set(RunState.pebbleStates.filter(\.isWaitingForPerson))
    #expect(live == Set<RunState>([.queued, .running, .retryWait]))
    #expect(waiting == Set<RunState>([.waitingApproval, .waitingInput, .paused]))
    #expect(RunState(rawValue: "from_a_newer_pebble").statusKey == nil)
    #expect(CardKind.simpleKinds == [.browserGrant, .screenGrant, .screenRaise])
    #expect(!CardKind.command.isSimple)
}

@Test func cardWordsArePebblesOwn() {
    let command: JSONValue = ["command": "npm test", "root": "/p", "writable": false]
    #expect(CardWords.heading(kind: .command, payload: command) == "npm test")
    #expect(CardWords.title(kind: .command, payload: command) == "Run npm test")
    #expect(CardWords.detail(kind: .command, payload: command) == "npm test")
    #expect(CardWords.summary(kind: .command, payload: command) == "Runs this command in your project without changing files.")
    #expect(
        CardWords.summary(kind: .command, payload: ["command": "rm -rf build", "writable": true])
            == "Runs this command in your project, where it can change files. Pebble can't undo a command.")
    #expect(CardWords.approveLabel(kind: .command, payload: command) == "Run command")
    #expect(CardWords.title(kind: .command, payload: ["command": "npm ci\nnpm test"]) == "Run npm ci …")

    let edit: JSONValue = ["path": "/p/src/auth/session.ts", "baseline": "abc", "scope_review": "Your request didn't ask to change tests."]
    #expect(CardWords.title(kind: .edit, payload: edit) == "Change session.ts")
    #expect(CardWords.title(kind: .edit, payload: ["path": "/p/NOTES.md", "baseline": .null]) == "Create NOTES.md")
    #expect(CardWords.detail(kind: .edit, payload: edit) == "/p/src/auth/session.ts")
    #expect(
        CardWords.summary(kind: .edit, payload: edit)
            == "Your request didn't ask to change tests. Changes this file in your project. You can undo it afterwards.")
    #expect(CardWords.approveLabel(kind: .edit, payload: edit) == "Apply edit")

    let check: JSONValue = ["recipe": "npm test", "check": ["path": "check.test.js", "content": "test()"], "check_run": ["recipe": "node"]]
    #expect(CardWords.title(kind: .tests, payload: check) == "Run an ad hoc check")
    #expect(CardWords.title(kind: .tests, payload: ["recipe": "pytest"]) == "Run isolated tests")
    #expect(CardWords.detail(kind: .tests, payload: ["plan": ["recipe": "pytest"]]) == "pytest")
    #expect(
        CardWords.summary(kind: .tests, payload: check)
            == "Runs the project's tests, then Pebble's own check alone, each in a temporary copy. Your project files don't change.")

    #expect(CardWords.title(kind: .git, payload: ["operation": "commit", "summary": "Commit 3 files"]) == "Git commit")
    #expect(CardWords.summary(kind: .git, payload: ["operation": "undo"]) == "Undoes an earlier Git change.")
    #expect(CardWords.title(kind: .plugin, payload: ["name": "Linear", "tool": "create_issue"]) == "Call Linear / create_issue")
    #expect(CardWords.title(kind: .install, payload: ["kind": "npm"]) == "Install dependencies (npm)")
    #expect(CardWords.title(kind: .file, payload: ["path": "/Users/me/notes.txt", "op": "edit"]) == "Edit notes.txt")
    #expect(CardWords.title(kind: .app, payload: ["name": "Preview", "document": "/Users/me/scan.pdf"]) == "Open scan.pdf in Preview")
    #expect(
        CardWords.summary(kind: .app, payload: ["name": "Preview", "document": "/Users/me/scan.pdf", "background": true])
            == "Opens /Users/me/scan.pdf in this app on your Mac, without bringing it to the front. Pebble won't control what happens inside it.")
    #expect(CardWords.title(kind: .url, payload: ["url": "https://example.com/a"]) == "Open https://example.com/a")
    #expect(CardWords.title(kind: .screenRaise, payload: ["app": "Notes"]) == "Bring Notes forward")
    #expect(CardWords.title(kind: .appAction, payload: ["app": "Music", "summary": "Play “Focus” in Music"]) == "Play “Focus” in Music")
    #expect(
        CardWords.title(kind: .browserGrant, payload: ["sites": ["https://www.youtube.com/", "https://youtube.com/watch", "news.example"]])
            == "Use youtube.com, news.example")
    #expect(CardWords.title(kind: CardKind(rawValue: "from_a_newer_pebble"), payload: [:]) == "Needs your review")
    #expect(CardWords.rejectLabel == "Don't allow")
}

@Test func screenCardsReadAsPebblesHeadings() {
    let press: JSONValue = [
        "review": [
            "action": "press", "element": ["label": "Send", "role": "AXButton"],
            "window": ["title": "Inbox — Mail", "origin": .null], "reasons": ["label_commit_word"],
        ]
    ]
    #expect(CardWords.title(kind: .screen, payload: press) == "Press “Send” in Inbox")
    #expect(
        CardWords.summary(kind: .screen, payload: press)
            == "Does this in the app window you shared. It may send, submit, save, delete or buy, and Pebble can't undo it.")
    let typing: JSONValue = ["review": ["action": "type_text", "text": "hello", "window": ["title": "Notes"]]]
    #expect(CardWords.summary(kind: .screen, payload: typing) == "Types this in the app window you shared. Pebble can't undo typing.")
    #expect(CardWords.detail(kind: .screen, payload: typing) == "hello")
    let keypress: JSONValue = ["review": ["action": "keypad", "window": ["title": ""]]]
    #expect(CardWords.summary(kind: .screen, payload: keypress) == "Presses this in the app window you shared. Pebble can't undo a press.")
    #expect(CardWords.title(kind: .screen, payload: keypress) == "Keypad in an app window")
    let grant: JSONValue = ["app": "Safari", "title": "Statement", "screenshots": true, "full_access": true]
    #expect(
        CardWords.summary(kind: .screenGrant, payload: grant)
            == "Lets Pebble see and use this one window in this conversation, for up to 15 minutes, with pictures of it when needed. In Full access Pebble runs the presses your messages ask for; anything that may spend money still asks. If macOS asks whether Pebble may bypass its window picker, choose Allow for the pictures.")
}

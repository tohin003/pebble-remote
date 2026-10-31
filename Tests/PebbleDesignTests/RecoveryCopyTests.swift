import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// Lane R's copy: Pebble's words for finishing and recovering a task (RecoveryCopy) and what a card holds
/// (CardDetailCopy), compared with Pebble's own files where Pebble has the words, and free of the words that never
/// reach the screen.
struct RecoveryCopyTests {
    // MARK: - Pebble's sentences and choices

    @Test func eachTaskStateIsASentenceAndAStateFromANewerPebbleSaysSo() {
        #expect(RecoveryCopy.Task.sentence(.verificationRequired) == "Pebble's change isn't verified yet.")
        #expect(RecoveryCopy.Task.sentence(.budgetExhausted) == "Reached this task's limit.")
        #expect(RecoveryCopy.Task.sentence(.failed) == "Stopped by an error.")
        #expect(RecoveryCopy.Task.sentence(RunState(rawValue: "teleported")) == "This task is in an unknown state.")
        #expect(
            RecoveryCopy.Task.sentence(.needsReconciliation, windowChecked: true)
                == "Checked: Pebble can use the window again. Send a message to continue.")
        #expect(
            RecoveryCopy.Task.sentence(.needsReconciliation, windowChecked: false)
                == "One step has an uncertain outcome. Check it before resuming.")
        #expect(RecoveryCopy.Task.sentence(.failed, windowChecked: true) == "Stopped by an error.")
    }

    @Test func outcomesNameTheirToolTheirVerdictAndTheirBasis() {
        #expect(RecoveryCopy.Outcomes.label(tool: "WriteFile", kind: "file") == "WriteFile (file)")
        #expect(RecoveryCopy.Outcomes.label(tool: nil, kind: nil) == "Tool call")
        #expect(RecoveryCopy.Outcomes.label(tool: "", kind: "") == "Tool call")
        #expect(RecoveryCopy.Outcomes.verdict("not_occurred") == "Pebble\u{2019}s readback shows this did not happen.")
        #expect(RecoveryCopy.Outcomes.verdict("something new") == "Pebble cannot tell whether this happened.")
        #expect(RecoveryCopy.Outcomes.basis("after_present") == "Basis: after present")
        #expect(RecoveryCopy.Outcomes.basis("") == "Basis: unknown")
        // A basis code with a word the app doesn't show says "record" instead.
        #expect(RecoveryCopy.Outcomes.basis("exit_" + "rece" + "ipt") == "Basis: exit record")
        #expect(RecoveryCopy.Outcomes.settleLabel("Shell") == "Settle Shell from Pebble\u{2019}s readback")
    }

    @Test func commandsHandoffsAndLimitsSayWhatPebbleSays() {
        #expect(RecoveryCopy.Command.summary("needs_reconciliation") == "Command: needs reconciliation")
        #expect(RecoveryCopy.Command.observation("effect_observed") == "Effect observed")
        #expect(RecoveryCopy.Command.observation("") == "Still uncertain after inspection")
        #expect(
            RecoveryCopy.Command.controlsHidden(3)
                == "Terminal control sequences hidden on this page: 3. The raw output bytes are kept.")
        #expect(RecoveryCopy.Handoff.className("device") == "Your Mac")
        #expect(RecoveryCopy.Handoff.className("unknown") == "An unrecorded route")
        #expect(RecoveryCopy.Handoff.className("cloud:claude") == "claude")
        #expect(RecoveryCopy.Handoff.withheld(0) == "No message is withheld.")
        #expect(RecoveryCopy.Handoff.withheld(1) == "Withheld: 1 message from another route class. It is not sent.")
        #expect(RecoveryCopy.Handoff.withheld(4) == "Withheld: 4 messages from another route class. They are not sent.")
        #expect(
            RecoveryCopy.Handoff.released(["device", "cloud:claude"])
                == "Released for this handoff, so sent although it came from another route class: Your Mac, claude.")
        #expect(RecoveryCopy.Handoff.role("assistant") == "Pebble\u{2019}s replies")
        #expect(RecoveryCopy.Handoff.role("anything else") == "Records Pebble kept")
        #expect(RecoveryCopy.Handoff.started(on: "cloud:chatgpt") == "Started a new run on chatgpt.")
        #expect(RecoveryCopy.Limits.minutes(1800) == "30 min")
        #expect(RecoveryCopy.Limits.minutes(90) == "1 min 30 s")
        #expect(RecoveryCopy.Limits.minutes(45) == "45 s")
        #expect(RecoveryCopy.PausedWindow.app(nil) == "The app" && RecoveryCopy.PausedWindow.app("mail") == "mail")
    }

    @Test func noRecoveryWordIsOneThatNeverReachesTheScreen() {
        var samples: [String] = []
        for state in RunState.pebbleStates { samples.append(RecoveryCopy.Task.sentence(state)) }
        samples += ["occurred", "not_occurred", "diverged", "unknown"].map(RecoveryCopy.Outcomes.verdict)
        samples += ["exit_" + "rece" + "ipt", "no_" + "rece" + "ipt", "after_present"].map(RecoveryCopy.Outcomes.basis)
        samples += ["still_uncertain", "effect_observed", "no_effect_observed"].map(RecoveryCopy.Command.observation)
        samples += ["user", "assistant", "other"].map(RecoveryCopy.Handoff.role)
        samples += [
            RecoveryCopy.Handoff.intro, RecoveryCopy.Handoff.upload("cloud:claude"), RecoveryCopy.Handoff.released(["device"]),
            RecoveryCopy.Command.unknownOutcome, RecoveryCopy.Command.passwordPrompt, RecoveryCopy.Outcomes.intro,
            RecoveryCopy.PausedWindow.sentence("mail"), RecoveryCopy.Held.acceptQuestion, RecoveryCopy.Limits.range,
            RecoveryCopy.AlwaysAllow.hint, RecoveryCopy.Undo.hint,
        ]
        for sample in samples {
            #expect(BannedWords.isClean(sample), "\(sample)")
        }
    }

    // MARK: - What a card holds

    @Test func anEditShowsItsDiffAndANewFileSaysSo() throws {
        let edit = try #require(CardDetailCopy.detail(kind: .edit, payload: ["path": "src/App.vue", "baseline": "1f", "diff": "-a\n+b"]))
        #expect(edit.button == "View Diff")
        #expect(edit.blocks == [.text("Proposed source edit · original stays intact until approval"), .diff("-a\n+b")])
        let draft = try #require(CardDetailCopy.detail(kind: .edit, payload: ["path": "src/New.vue"]))
        #expect(draft.blocks == [.text("New file draft · original stays intact until approval"), .diff("No changes")])
    }

    @Test func anAdHocCheckShowsTheCheck() throws {
        let check = try #require(
            CardDetailCopy.detail(
                kind: .tests,
                payload: ["recipe": "pytest", "check": ["path": "tests/test_pebble_check.py", "content": "def test(): pass"]]))
        #expect(check.button == "View the Check")
        #expect(
            check.blocks == [
                .text(
                    "pytest with tests/test_pebble_check.py added to a temporary project copy. It doesn't count as your project's tests. Network and original project writes are blocked."
                ),
                .code("def test(): pass"),
            ])
        let plain = try #require(CardDetailCopy.detail(kind: .tests, payload: ["recipe": "npm test"]))
        #expect(plain.button == "Details")
        #expect(
            plain.blocks == [.text("npm test in a temporary project copy. Network and original project writes are blocked.")])
        let planned = try #require(
            CardDetailCopy.detail(
                kind: .tests,
                payload: ["recipe": "npm test", "plan": ["recipe": "npm test", "argv": ["npm", "test"], "timeout": 300, "network": false]]))
        #expect(planned.button == "Technical Details")
        #expect(planned.blocks.contains(.title("Test recipe npm test")) && planned.blocks.contains(.code("npm test")))
        guard case .technical(let inner)? = planned.blocks.last else {
            Issue.record("expected Technical details last")
            return
        }
        #expect(inner.contains(.facts([
            .init(name: "Recipe", value: "npm test"), .init(name: "Timeout", value: "300 seconds"),
            .init(name: "Output limit", value: "not reported"), .init(name: "Network", value: "denied"),
        ])))
    }

    @Test func aCommandShowsItsRiskFolderAndPlan() throws {
        let unplanned = try #require(
            CardDetailCopy.detail(
                kind: .command,
                payload: [
                    "command": "npm test", "root": "/Users/me/docs", "risk": "Project script", "network": false,
                    "writable": false, "guard_review": "The tests read fixtures outside the project.",
                ]))
        #expect(unplanned.button == "Technical Details")
        #expect(Array(unplanned.blocks.prefix(4)) == [
            .text("Project script · Selected project only · Network denied. Read only."), .code("npm test"),
            .note("/Users/me/docs"), .why(["The tests read fixtures outside the project."]),
        ])
        #expect(unplanned.blocks.contains { if case .note(let text) = $0 { text.hasPrefix("Unplanned command:") } else { false } })
        let planned = try #require(
            CardDetailCopy.detail(
                kind: .command,
                payload: [
                    "command": "git log", "risk": "Read", "network": true, "writable": true,
                    "plan": [
                        "steps": [["argv": ["git", "log", "--format=%s %an"], "cwd": "."]], "pipeline": "single",
                        "network": ["mode": "none"], "plan_hash": "0123456789abcdef0123",
                    ],
                ]))
        #expect(planned.blocks.first == .text("Read · Selected project only · Network access requested. Project writes allowed."))
        #expect(planned.blocks.contains(.code("git log \"--format=%s %an\"")))
        guard let technical = planned.blocks.compactMap({ if case .technical(let inner) = $0 { inner } else { nil } }).first,
            case .facts(let facts)? = technical.last
        else {
            Issue.record("expected the plan's facts")
            return
        }
        #expect(facts.contains(.init(name: "Network", value: "denied")) && facts.contains(.init(name: "Writable", value: "read-only")))
        #expect(facts.contains(.init(name: "Plan hash", value: "0123456789ab")))
    }

    @Test func aGitPlanAnInstallAndAWindowSayItInThePhonesPlaces() throws {
        let git = try #require(
            CardDetailCopy.detail(
                kind: .git,
                payload: [
                    "operation": "reset", "destructive": true, "summary": "Moves main back one commit.",
                    "bindings": ["head_ref": "refs/heads/main", "head_commit": "abcdef0123456789abcd"], "undo_of": "rcp-1",
                ]))
        #expect(git.blocks.first == .title("Git reset"))
        #expect(git.blocks.contains(.badges([.init(text: "Destructive", isAlert: true)])))
        let technical = try #require(git.blocks.compactMap { if case .technical(let inner) = $0 { inner } else { nil } }.first)
        guard case .facts(let facts)? = technical.last else {
            Issue.record("expected the plan's facts")
            return
        }
        #expect(facts.contains(.init(name: "Branch", value: "main")) && facts.contains(.init(name: "Undo of change", value: "rcp-1")))
        let install = try #require(CardDetailCopy.detail(kind: .install, payload: ["network": "allowlisted_registry_only"]))
        #expect(install.blocks.contains { if case .note(let text) = $0 { text.contains("through Pebble's proxy.") } else { false } })
        #expect(install.blocks.contains(.note("No registry was reported.")))
        let grant = try #require(CardDetailCopy.detail(kind: .screenGrant, payload: ["app": "Calculator", "abilities": ["look", "press"]]))
        #expect(grant.blocks.last == .note(
            "Only this window. Pebble stops at sign-ins, codes and checks and hands them to you. End access any time in Control › Shared Windows."))
        #expect(grant.blocks.contains(.label("In this conversation, for up to 15 minutes, Pebble could")))
        #expect(CardDetailCopy.detail(kind: .app, payload: ["name": "Notes"]) == nil)
    }

    @Test func aConnectorCallShowsItsArgumentsAsPebblesCardDoes() throws {
        let plugin = try #require(
            CardDetailCopy.detail(kind: .plugin, payload: ["url": "https://mcp.example.com", "arguments": ["q": "weather", "n": 3]]))
        #expect(plugin.button == "Details")
        #expect(plugin.blocks.first == .text("External tool call · https://mcp.example.com. Review the arguments before allowing this call."))
        guard case .code(let arguments)? = plugin.blocks.last else {
            Issue.record("expected the arguments")
            return
        }
        #expect(arguments.contains("\"n\" : 3") && arguments.contains("\"q\" : \"weather\""))
    }

    @Test func pebblesHelpersShowOnlyWhatWasReported() {
        #expect(CardDetailCopy.text(.string(String(repeating: "a", count: 12)), 10)
            == "aaaaaaaaaa … [truncated for display: 10 of 12 characters shown]")
        #expect(CardDetailCopy.short(.string("0123456789abcdef0123")) == "0123456789ab")
        #expect(CardDetailCopy.short(.string("main")) == "main")
        #expect(CardDetailCopy.bytes(1536) == "1.5 KiB" && CardDetailCopy.bytes(1_048_576) == "1 MiB")
        #expect(CardDetailCopy.bytes(512) == "512 bytes" && CardDetailCopy.bytes(nil) == "not reported")
        #expect(CardDetailCopy.seconds(300) == "300 seconds" && CardDetailCopy.number(.bool(true)) == "not reported")
        #expect(CardDetailCopy.argv(["echo", "two words", ""]) == "echo \"two words\" \"\"")
        #expect(CardDetailCopy.rows([("A", ""), ("B", "b")]) == [.init(name: "B", value: "b")])
    }

    @Test func noCardDetailSaysAWordThatNeverReachesTheScreen() {
        let payloads: [(CardKind, JSONValue)] = [
            (.edit, ["path": "a.txt", "diff": "+x"]),
            (.tests, ["recipe": "npm test", "check": ["path": "c.py", "content": "x"], "check_run": ["recipe": "pytest"], "plan": ["argv": ["npm", "test"]]]),
            (.command, ["command": "ls", "plan": ["steps": [["argv": ["ls"], "stdin": "pty"]], "interactive": true, "network": ["mode": "broker", "destinations": [["api.example.com", 443]], "credentials": [["ref": "token", "destination": ["api.example.com", 443], "methods": ["GET"]]]]]]),
            (.command, ["command": "rm -rf build", "effect": "Sets NAME=value."]),
            (.git, ["operation": "push", "publication": true, "destructive": true, "bindings": ["remote_ref": "refs/heads/main", "force": true, "remote_path": "/tmp/r.git"], "sensitive_findings": [["path": "k.pem", "kind": "key"]], "message": "Fix", "effects": ["Moves main"]]),
            (.worktree, ["operation": "allocate_child_worktree", "disclosure": "A copy.", "effects": ["Creates a folder"]]),
            (.install, ["network": "anything", "registries": [["registry.npmjs.org", 443]], "summary": "Installs 3 packages."]),
            (.shell, ["command": "curl x", "reasons": ["Reaches the network"], "hosts": ["a.example"], "folders": ["/tmp"], "snapshot_paths": ["/tmp/x"], "always_offered": false]),
            (.file, ["path": "/Users/me/n.txt", "op": "edit", "old_string": "a", "new_string": "b", "gated": "~/.zshrc"]),
            (.screen, ["review": ["action": "press", "element": ["label": "Send", "role": "AXButton"], "window": ["title": "New Message"], "reasons": ["form_submit"], "consent": "foreground_input", "context": [["label": "To"]]]]),
            (.url, ["url": "https://example.com", "why": "To read it.", "route": "table", "site": "example.com", "query": "x", "reasons": ["Asked"]]),
            (.screenGrant, ["app": "Mail", "title": "Inbox", "abilities": ["look", "fill", "press"], "full_access": true, "off_space": true, "why": "To send."]),
            (.browserGrant, ["sites": ["example.com"], "read": ["docs.example.com"], "route": "window", "browser_name": "Safari", "url": "https://example.com", "abilities": ["press"]]),
            (.appAction, ["app": "Notes", "summary": "Make a note", "args": ["title": "Shopping", "text": "Milk"], "reasons": ["Asked"]]),
            (.screenRaise, ["app": "Notes", "title": "Shopping", "minimized": true]),
        ]
        for (kind, payload) in payloads {
            guard let detail = CardDetailCopy.detail(kind: kind, payload: payload) else {
                Issue.record("expected details for \(kind.rawValue)")
                continue
            }
            for text in Self.words(detail.blocks) + [detail.button] {
                #expect(BannedWords.isClean(text), "\(kind.rawValue): \(text)")
            }
        }
    }

    static func words(_ blocks: [CardDetailCopy.Block]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .title(let text), .text(let text), .note(let text), .alert(let text), .label(let text), .code(let text),
                .diff(let text):
                [text]
            case .badges(let badges): badges.map(\.text)
            case .why(let items), .list(let items): items
            case .facts(let facts): facts.flatMap { [$0.name, $0.value] }
            case .technical(let inner): words(inner)
            }
        }
    }
}

/// The recovery words are Pebble's, compared with its files (read-only) when the checkout is on this Mac.
@Suite(.enabled(if: PebbleCheckout.url != nil))
struct RecoveryParityTests {
    static func source(_ file: String) throws -> String { try PebbleParityTests.read(file) }

    /// Pebble's sentence, as its file holds it.
    static func has(_ text: String, in file: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try source(file).contains(text), "\(file) lacks: \(text)", sourceLocation: sourceLocation)
    }

    /// A button label: Pebble's words, in Apple's title style on the phone.
    static func label(_ text: String, in file: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(
            try source(file).lowercased().contains(text.lowercased()), "\(file) lacks the label: \(text)",
            sourceLocation: sourceLocation)
    }

    @Test func runPanelsWordsAreWordForWord() throws {
        let file = "src/components/RunPanel.vue"
        for state in RunState.pebbleStates {
            try Self.has(RecoveryCopy.Task.sentence(state), in: file)
        }
        for text in [
            RecoveryCopy.Task.unknown, RecoveryCopy.Task.checked, RecoveryCopy.Held.title, RecoveryCopy.Held.acceptQuestion,
            RecoveryCopy.Limits.stepLimit, RecoveryCopy.Limits.activeSeconds, RecoveryCopy.Task.label,
            RecoveryCopy.PausedWindow.sentence("{{ item.app }}"), RecoveryCopy.PausedWindow.label(""),
            RecoveryCopy.PausedWindow.theApp,
        ] {
            try Self.has(text, in: file)
        }
        for text in [
            RecoveryCopy.Task.resume, RecoveryCopy.Task.details, RecoveryCopy.Held.runTheTests,
            RecoveryCopy.Held.askPebbleToFinish, RecoveryCopy.Held.acceptAsUnverified, RecoveryCopy.Held.cancel,
            RecoveryCopy.PausedWindow.done, RecoveryCopy.PausedWindow.endAccess,
        ] {
            try Self.label(text, in: file)
        }
        try Self.has(RecoveryCopy.Limits.range, in: "backend/pebble/runtime.py")
    }

    @Test func reconcilePanelsWordsAreWordForWord() throws {
        let file = "src/components/ReconcilePanel.vue"
        for text in [
            RecoveryCopy.Outcomes.intro, RecoveryCopy.Outcomes.waitsForTask, RecoveryCopy.Outcomes.none,
            RecoveryCopy.Outcomes.reportYourself, RecoveryCopy.Outcomes.happened, RecoveryCopy.Outcomes.didNotHappen,
            RecoveryCopy.Outcomes.whatYouChecked(""), "Tool call", "Basis: ",
        ] + ["occurred", "not_occurred", "diverged", "unknown"].map(RecoveryCopy.Outcomes.verdict) {
            try Self.has(text, in: file)
        }
        for text in [RecoveryCopy.Outcomes.settle, RecoveryCopy.Outcomes.record, RecoveryCopy.Outcomes.title] {
            try Self.label(text, in: file)
        }
        try Self.has(" from Pebble\u{2019}s readback", in: file)
    }

    @Test func executionOutputsWordsAreWordForWord() throws {
        let file = "src/components/ExecutionOutput.vue"
        for text in [
            RecoveryCopy.Command.unknownOutcome, RecoveryCopy.Command.observedOutcome, RecoveryCopy.Command.inspectionNote,
            RecoveryCopy.Command.inspectionNoteHint, RecoveryCopy.Command.inspectionRecorded,
            RecoveryCopy.Command.passwordPrompt, RecoveryCopy.Command.typeIntoField, RecoveryCopy.Command.partialOutput,
            "Terminal control sequences hidden on this page: ", "The raw output bytes are kept.", "Command: ",
            RecoveryCopy.Command.output,
        ] + ProcessObservationNames.all.map(RecoveryCopy.Command.observation) {
            try Self.has(text, in: file)
        }
        for text in [
            RecoveryCopy.Command.typeInto, RecoveryCopy.Command.sendLine, RecoveryCopy.Command.ctrlC,
            RecoveryCopy.Command.ctrlD, RecoveryCopy.Command.readOutput, RecoveryCopy.Command.nextOutputPage,
            RecoveryCopy.Command.stop, RecoveryCopy.Command.forgetOutput, RecoveryCopy.Command.recordInspection,
        ] {
            try Self.label(text, in: file)
        }
    }

    @Test func modelHandoffsWordsAreWordForWord() throws {
        let file = "src/components/ModelHandoff.vue"
        for text in [
            RecoveryCopy.Handoff.title, RecoveryCopy.Handoff.intro, RecoveryCopy.Handoff.checking,
            RecoveryCopy.Handoff.review, RecoveryCopy.Handoff.approvedNothingSent, "Started a new run on ",
            RecoveryCopy.Handoff.from, RecoveryCopy.Handoff.to, RecoveryCopy.Handoff.destinationFingerprint,
            "The messages counted below will be uploaded to ", "Messages that will be sent: ", RecoveryCopy.Handoff.role,
            RecoveryCopy.Handoff.nothingSent, RecoveryCopy.Handoff.withheld(0),
            "Withheld: 1 message from another route class. It is not sent.", " messages from another route class. They are not sent.",
            RecoveryCopy.Handoff.withheldIDs, "Released for this handoff, so sent although it came from another route class: ",
            RecoveryCopy.Handoff.role("user"), RecoveryCopy.Handoff.role("assistant"), RecoveryCopy.Handoff.thisDevicePebble,
            RecoveryCopy.Handoff.className("unknown"), RecoveryCopy.Handoff.approved,
        ] {
            try Self.has(text, in: file)
        }
        for text in [RecoveryCopy.Handoff.approve, RecoveryCopy.Handoff.start, RecoveryCopy.Handoff.reviewAgain] {
            try Self.label(text, in: file)
        }
    }

    @Test func appsUndoAlwaysAllowAndHandoffWordsAreWordForWord() throws {
        let file = "src/App.vue"
        for text in [
            RecoveryCopy.Handoff.section, RecoveryCopy.Undo.editUndone, RecoveryCopy.Undo.commandUndone,
            RecoveryCopy.Undo.changeUndone, RecoveryCopy.Undo.someChangesNotUndone, RecoveryCopy.Undo.undoPlanReady,
        ] {
            try Self.has(text, in: file)
        }
        for text in [
            RecoveryCopy.Handoff.notNow, RecoveryCopy.Undo.edit, RecoveryCopy.Undo.command, RecoveryCopy.Undo.change,
            RecoveryCopy.Undo.gitPlan, RecoveryCopy.AlwaysAllow.button, CardDetailCopy.viewDiff, CardDetailCopy.viewTheCheck,
        ] {
            try Self.label(text, in: file)
        }
        // The card body's sentences (Pebble's template spreads them over lines).
        for text in [
            "Proposed source edit", "New file draft", "· original stays intact until approval", "External tool call · ",
            "arguments before allowing this call.", "in a temporary project copy. Network",
            "and original project writes are blocked.",
        ] {
            try Self.has(text, in: file)
        }
    }

    @Test func actionReviewsSentencesAreWordForWordSaveThePhonesThreePlaces() throws {
        let file = "src/components/ActionReview.vue"
        try Self.has(CardDetailCopy.untrusted, in: file)
        try Self.label(CardDetailCopy.technicalDetails, in: file)
        let fixed = [
            "Dirty work is not copied: uncommitted project changes stay where they are and are never copied or discarded. The child writes only inside this folder.",
            "Publication: this copies commits into another repository. Only local bare repositories are supported.",
            "Unplanned command: the text could not be expressed as an exact argv plan, so its executable is resolved when it runs. Review the command text above carefully.",
            "Uses saved command credentials. The value is added by Pebble's broker on these routes only and is never visible to the command.",
            "Interactive: the model may type into this command's terminal, except at password prompts, which only you can answer.",
            "Pebble keeps a copy of what this may change first, so you can undo it.",
            "Pebble asks about this every time; it cannot be allowed always.",
            "Pebble keeps a copy of the file first, so you can undo it.",
            "This may send, submit, save, delete or buy, so it waits for you. Pebble can't undo it and never retries it.",
            "Pebble can't undo a press, so this one waits for you. It is never retried.",
            "Pebble only asks macOS to open it; it can't see the page.",
            "Pebble reads only that window's page, and only while it shows these sites.",
            "Pebble asks once in this conversation; after that it brings this window forward without asking.",
            "This window is on another desktop, so what Pebble reads there may be out of date.",
            "look around (focus, scroll, open and close sections)",
            "fill in (choose options, tick boxes, type text; never a password, code or card field)",
            "press buttons (each press waits for you, except keypad keys, board squares, tabs, checkboxes and switches)",
            "Only this window. Pebble stops at sign-ins, codes and checks and hands them to you. End access any time in ",
        ]
        for text in fixed { try Self.has(text, in: file) }
        // The phone's three places: Pebble's own sentence names the Mac's place or an internal word.
        try Self.has("End access any time in Details › Tools (⇧⌘D).", in: file)
        try Self.has("through the host proxy.", in: file)  // lint-copy: allow (Pebble's own sentence, in a test)
    }
}

/// ExecutionOutput's three observations, by Pebble's values.
enum ProcessObservationNames {
    static let all = ["still_uncertain", "effect_observed", "no_effect_observed"]
}

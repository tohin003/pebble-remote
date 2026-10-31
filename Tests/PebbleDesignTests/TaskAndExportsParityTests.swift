import Foundation
import Testing

@testable import PebbleDesign

/// Lane T: the words of goal editing, a helper agent's screen, a view's revisions and Stop, and exports are Pebble's
/// own, found in its sources when the Pebble checkout is on this Mac (whitespace collapsed, as a template wraps its
/// lines). Where the phone says something else (your Mac, Stop view), the test pins what Pebble says and what the phone
/// says.
@Suite(.enabled(if: PebbleCheckout.url != nil))
struct TaskAndExportsParityTests {
    typealias G = AppCopy.Goals
    typealias H = AppCopy.ViewHistory
    typealias X = AppCopy.Exports

    static func source(_ path: String) throws -> String {
        PebbleParityTests.collapse(try PebbleParityTests.read(path))
    }

    static func expectAll(_ texts: [String], in path: String, sourceLocation: SourceLocation = #_sourceLocation) throws
    {
        let text = try source(path)
        for piece in texts {
            #expect(text.contains(piece), "\(path) no longer says: \(piece)", sourceLocation: sourceLocation)
        }
    }

    // MARK: Goal editing (DT-08, DT-11, DT-12, DT-13)

    @Test func goalEditingWordsArePebbles() throws {
        let path = "src/components/GoalPanel.vue"
        try Self.expectAll(
            [
                ">\(G.edit)</button>", "'\(G.editCriterion(""))' + c.id", ">\(G.save)</button>",
                "`\(G.criterionUpdated("${c.id}"))`", G.noSteps, "<label>\(G.newStep)<input",
                "placeholder=\"\(G.stepPlaceholder)\"",
                "<legend>\(G.after)</legend>", "<th scope=\"col\">\(G.after)</th>", ">\(G.addStep)</button>",
                "\"\(G.stepAdded)\"",
                "<label>\(G.blockStep)<select", "<label>\(G.reason)<input", "placeholder=\"\(G.reasonPlaceholder)\"",
                ">\(G.blockStep)</button>", "`\(G.stepBlocked("${step}"))`", "'\(G.unblockStep(""))' + s.id",
                ">\(G.unblock)</button>",
                "`\(G.stepUnblocked("${s.id}"))`", "maxlength=\"240\"", "maxlength=\"500\"", "maxlength=\"300\"",
                "{{ s.id }} · {{ s.title }}", "<th scope=\"col\">\(G.criterion)</th>",
                "s.ready ? \"ready\" : \"—\"", "(s.blocker.active ? \"\" : \" (resolved)\")",
                "`${base}: ${s.blocker.ref}`",
                ">\(G.review)</button>",
            ], in: path)
        let kinds = try SettingsControlsParityTests.pairs(in: path, from: "const blockerKinds", to: "};")
        #expect(kinds.count == 4)
        for (kind, words) in kinds { #expect(G.blockerKind(kind) == words, "blockerKinds.\(kind)") }
        #expect(G.blockerKind("anything else") == "unknown")
        // Pebble's caption names its own records "host records"; the phone keeps only "Blockers".
        try Self.expectAll(["<caption>\(G.blockers) (host records)</caption>"], in: path)  // lint-copy: allow
        #expect(BannedWords.isClean(G.blockers))
        // The Next column's other two lines name places on the Mac; the phone's name its own places.
        try Self.expectAll(["Answer it in the task panel", "Inspect it in the task panel"], in: path)
        #expect(G.stepBlocker(kind: "text", ref: "Waiting", active: true, ready: false) == "Your note: Waiting")
        #expect(G.stepBlocker(kind: "approval", ref: "a1", active: false, ready: false) == "Review (resolved)")
        #expect(G.stepBlocker(kind: nil, ref: nil, active: true, ready: true) == "ready")
        #expect(G.afterSteps(["s1", "s2"]) == "After s1, s2" && G.afterSteps([]) == nil)
    }

    @Test func goalLimitsArePebbles() throws {
        let goals = try PebbleParityTests.read("backend/pebble/goals.py")
        #expect(goals.contains("TITLE, TEXT, BLOCKER_TEXT = 240, 500, 300"))
        #expect(goals.contains("MAX_STEPS = 20") && goals.contains("MAX_DEPENDS = 8"))
        #expect(
            goals.contains("f'A goal holds up to {MAX_STEPS} steps.'")
                && G.stepsFull(20) == "A goal holds up to 20 steps.")
    }

    // MARK: A helper agent (DT-21)

    @Test func theAgentScreensWordsArePebbles() throws {
        let path = "src/components/AgentPanel.vue"
        try Self.expectAll(
            [
                G.loadingAgent, "<summary>\(G.technicalDetails)</summary>", "'Used ' + parts.join(', ')",
                "' model call'",
                "' model calls'", "' tokens'", "' s'", "<strong>\(G.resultRecord)</strong>", "Write paths: {{",
                "Dependencies: {{",
                "Evidence: {{", "aria-label=\"\(G.agentLimits)\"", "['Dispatches', detail.value?.dispatches]",
                "['Charged tokens', detail.value?.charged_tokens]", "['Model seconds', detail.value?.elapsed]",
                "label + ': ' + value).join(' · ')", "Generation {{ row.node.generation ?? 1 }} · Tools: {{",
                "|| 'none' }}", " · Review: {{ row.node.review }}", "Agent: {{ detail.agent_id }}",
                " · Parent: {{ detail.parent_id }}",
                "task.length > 120 ? task.slice(0, 119) + '…' : task", "{ title: 'Tool records'", "{ title: 'Messages'",
                "{ title: 'Questions'", "{ title: 'Patches'", "{ title: 'Execution requests'",
                "new Set(['queued', 'running', 'waiting_parent', 'waiting_input'])", "new Set(['interrupted'])",
                "'completed', 'failed', 'stopped', 'budget_exhausted'", ": 'unknown'",
            ], in: path)
        #expect(
            G.used(calls: 1, tokens: 4180, seconds: 21.4)
                == "Used 1 model call, \(AppCopy.Details.grouped(4180)) tokens, 21 s")
        #expect(G.used(calls: nil, tokens: nil, seconds: nil) == nil)
        #expect(
            G.accounting(dispatches: 3, tokens: 4180, seconds: 21.4)
                == "Dispatches: 3 · Charged tokens: 4180 · Model seconds: 21.4")
        #expect(
            G.records("effects", count: 2) == "Execution requests (2)"
                && G.records("receipts", count: 1) == "Tool records (1)")  // lint-copy: allow
        #expect(G.agentStatus("budget_exhausted") == "budget exhausted" && G.agentStatus("new_state") == "unknown")
        #expect(G.rowLine(task: String(repeating: "a", count: 130), used: nil)?.count == 120)
        // Pebble's "Task: {id}" names the agent's own id again (agent_tree.py `_public`); the phone says it once.
        #expect(
            try PebbleParityTests.read("backend/pebble/agent_tree.py").contains("result.update(agent_id=result['id']"))
    }

    // MARK: A view's revisions and Stop (CV-01, CV-02, CV-08, CV-09)

    @Test func aViewsRevisionWordsArePebbles() throws {
        try Self.expectAll(
            [
                "historical ? \"Earlier version\" : \"Version\" }} {{ active.revision || 1 }}",
                ">Current · revision {{ currentRevision }}<",
                "Revision {{ snapshot.revision }} · {{ snapshot.status || 'ready' }}",
                "<label class=\"artifact-revision-label\">Revision",
                ">Export…</button>", ">Refresh</button>", "'Stop artifact'",
            ], in: "src/components/ArtifactPanel.vue")
        #expect(H.earlierVersion(2) == "Earlier version 2" && H.current(3) == "Current · revision 3")
        #expect(
            H.earlier(2, status: nil) == "Revision 2 · ready"
                && H.earlier(1, status: "stopped") == "Revision 1 · stopped")
        try Self.expectAll([H.earlierNote(kind: "form")], in: "src/components/NativeArtifactRenderer.vue")
        try Self.expectAll([H.earlierNote(kind: "quiz")], in: "src/components/QuizRenderer.vue")
        try Self.expectAll([H.earlierNote(kind: "dashboard")], in: "src/components/DashboardRenderer.vue")
        // "Stop view" is Pebble's own words for stopping its HTML view; the phone uses them for every view.
        try Self.expectAll(["Stop view</button"], in: "src/components/ArtifactPanel.vue")
        #expect(H.stop == "Stop view" && H.export == "Export\u{2026}")
    }

    // MARK: Exports (DT-26 to DT-31)

    @Test func theExportWordsArePebbles() throws {
        let path = "src/components/ExportPanel.vue"
        try Self.expectAll(
            ["html", "docx", "xlsx", "csv"].map { "{ id: '\($0)', label: '\(X.formatName($0))' }" }
                + [
                    X.includeAnswers, "'\(X.checking)' : '\(X.preview)'", "'\(X.previewReady)'",
                    "'\(X.optionsChanged)'",
                    "`\(X.viewChanged(0).replacingOccurrences(of: "0", with: "${props.source.revision ?? '?'}"))`",
                    "source.title || '\(X.thisSource)'", "'Creating…' : '\(X.createFile)'", "'\(X.creating)'",
                    ">\(X.cancel)</button>", ">\(X.deleteCopy)</button>",
                    "'\(X.deleted.replacingOccurrences(of: "'", with: "\\'"))'",
                    "'\(X.saveOnMac(verified: true))' : '\(X.saveOnMac(verified: false))'",
                    "aria-label=\"\(X.checks)\"",
                    "check.passed ? 'Passed' : 'Did not pass'", " · preview valid until {{",
                    " · about {{ plan.pages }} page(s)",
                    "% of the source text found", " · SHA-256 {{ receipt.sha256.slice(0, 12) }}…",
                    "'Verified copy' : 'Unverified copy'", " · not published", "Saved to {{ saved.path }}",
                    ">\(X.format)</legend>", "' sheet(s)'", "' page(s)'", "' MB'", "' KB'",
                ], in: path)
        for status in ["verified", "unverified", "unavailable", "failed", "cancelled"] {
            try Self.expectAll(["\(status): '\(X.verdictNote(status))'"], in: path)
        }
        for status in ["Verified", "Unverified", "Unavailable", "Cancelled", "Failed"] {
            try Self.expectAll(["'\(status)'"], in: path)
        }
        // Pebble's note says "this Mac"; the phone says "your Mac".
        try Self.expectAll([X.note.replacingOccurrences(of: "your Mac", with: "this Mac")], in: path)
        try Self.expectAll([">\(X.title)</h3>", ">\(X.view)<select"], in: "src/App.vue")
        #expect(X.size(2048) == "2 KB" && X.size(3 << 20) == "3.0 MB" && X.size(10) == "1 KB")
        #expect(X.verdict("unverified", format: "docx") == "Unverified · DOCX")
        #expect(
            X.fileLine(
                name: "a.csv", bytes: 412, sheets: 1, pages: nil, coverage: 0.9987, revision: 2,
                sha256: "0123456789abcdef")
                == "a.csv · 1 KB · 1 sheet(s) · 99.8% of the source text found · revision 2 · SHA-256 0123456789ab…")
        #expect(
            X.fileLine(name: "a", bytes: nil, sheets: nil, pages: nil, coverage: nil, revision: nil, sha256: nil) == nil
        )
        #expect(X.check(passed: false, label: "No macros", detail: "") == "Did not pass: No macros")
    }

    @Test func everyNewWordIsClean() {
        let words = [
            G.checkClears, G.answerInConversation, G.inspectInActivity, G.writtenByPebble, G.reviewGone, G.reviewHint,
            G.opensAgentHint, H.stopTitle, H.stopMessage(waitingForm: true), H.stopMessage(waitingForm: false),
            X.note, X.opensHint, X.deleteTitle, X.deleteMessage, X.saveOnMacNote, X.earlierFiles, X.noEarlierFiles,
            X.verdictNote("discarded"), X.verdictWord("discarded"),
        ]
        for word in words { #expect(BannedWords.isClean(word), "\(word)") }
    }
}

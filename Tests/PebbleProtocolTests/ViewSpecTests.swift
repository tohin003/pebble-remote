import Foundation
import Testing

@testable import PebbleProtocol

// Lane G: pebble-ui-spec v1 (contract 3.12) against Pebble's own fixtures. The file is read where claude-w published
// it, next to this repository: ../pebble-ui-spec-v1/fixtures.json (sha256 8e7c3bab33619edf…, posted
// 2026-10-30 15:56). Pebble's builders made every work-view example, so these are the views the phone will receive.

private enum SpecFixtures {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("pebble-ui-spec-v1/fixtures.json")

    /// The spec sits next to this repository on the Mac it was made on; elsewhere these tests skip rather than fail.
    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func load() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
}

/// An activity item as the work view needs it.
private struct SpecItem: WorkItem, Hashable {
    var seq: Int
    var status: String
    var label: String
    var workView: WorkView?

    init?(_ json: JSONValue?) {
        guard let json, let seq = json["seq"]?.int, let label = json["label"]?.string else { return nil }
        self.seq = seq
        status = json["status"]?.string ?? "done"
        self.label = label
        workView = WorkView(json: json["view"])
    }
}

@Test(.enabled(if: SpecFixtures.exists, "the spec's fixtures sit next to this repository")) func everyFixtureItemDecodesByType() throws {
    let fixtures = try SpecFixtures.load()
    let names = (fixtures["summary_items"]?.array ?? []).compactMap(\.string)
    #expect(names.count == 20)
    for name in names {
        let raw = fixtures["items"]?[name]
        let item = try #require(SpecItem(raw), "item \(name) is unreadable")
        let type = raw?["view"]?["type"]?.string
        if let type, WorkView.types.contains(type) {
            #expect(item.workView?.type == type, "\(name) should decode as \(type)")
        } else {
            // Rule 1: an unknown type is not drawn; the item shows its label and detail instead.
            #expect(item.workView == nil, "\(name) has an unknown type and must fall back")
        }
    }
}

@Test(.enabled(if: SpecFixtures.exists, "the spec's fixtures sit next to this repository")) func fixtureViewsKeepTheirFields() throws {
    let items = try #require(try SpecFixtures.load()["items"])
    func view(_ name: String) -> WorkView.Content? { WorkView(json: items[name]?["view"])?.content }

    guard case .command(let command)? = view("command") else { Issue.record("command"); return }
    #expect(command.command == "npm run build" && command.place == "Project folder" && command.usesNetwork == false)
    #expect(command.exit == 0 && command.seconds == 4.6 && command.state == .done && command.tail.count == 5)
    #expect(command.tail.last == "Done in 4.2 s" && command.actionID == "act_command" && !command.isCut)

    guard case .command(let failed)? = view("command_failed") else { Issue.record("command_failed"); return }
    #expect(failed.exit == 2 && failed.state == .failed && failed.place == "Project folder › scripts")
    #expect(failed.command == "python3 scripts/deploy.py --token=***")

    guard case .read(let read)? = view("read") else { Issue.record("read"); return }
    #expect(read.path == "src/auth/session.py" && read.start == 1 && read.total == 212 && !read.isPrivate)
    guard case .read(let secret)? = view("read_private") else { Issue.record("read_private"); return }
    #expect(secret.isPrivate && secret.path == nil)

    guard case .search(let search)? = view("search") else { Issue.record("search"); return }
    #expect(search.tool == .grep && search.query == "refresh_session" && search.hits == 7)
    guard case .web(let web)? = view("web") else { Issue.record("web"); return }
    #expect(web.sites == ["rfc-editor.org", "docs.python.org", "example.org"])

    guard case .edit(let edit)? = view("edit_waiting") else { Issue.record("edit_waiting"); return }
    #expect(edit.isNew && edit.state == .waiting && edit.added == 2 && edit.removed == 0)

    guard case .tests(let tests)? = view("tests") else { Issue.record("tests"); return }
    #expect(tests.passed == 41 && tests.failed == 1 && tests.total == 42 && tests.state == .failed)
    #expect(tests.failing == ["tests/test_session.py::test_refresh_expired_session"] && tests.recipe == "python-pytest")

    guard case .git(let status)? = view("git_status") else { Issue.record("git_status"); return }
    #expect(status.ahead == 3 && status.behind == 2 && status.changed == 4 && status.operation == "status")
    guard case .git(let commit)? = view("git_commit") else { Issue.record("git_commit"); return }
    #expect(commit.commit == "a1b2c3d4e5f6" && !commit.isDestructive && !commit.publishes && commit.state == .done)

    guard case .window(let window)? = view("window") else { Issue.record("window"); return }
    #expect(window.verdict == .happened && window.before == "12*7" && window.after == "84" && window.point == nil)
    #expect(window.picture == WorkView.Window.Picture(width: 320, height: 480))
    guard case .window(let click)? = view("window_click") else { Issue.record("window_click"); return }
    #expect(click.verdict == .nothingChanged && click.pressInFrame?.point == WorkView.Window.Point(x: 212, y: 388))

    guard case .agent(let agent)? = view("agent") else { Issue.record("agent"); return }
    #expect(agent.name == "tests" && agent.depth == 1 && agent.tokens == 5200 && agent.state == .done)

    guard case .checks(let checks)? = view("checks") else { Issue.record("checks"); return }
    #expect(checks.requirements.count == 3 && checks.requirements.allSatisfy { $0.state == .met } && checks.wasRepaired)
    #expect(checks.tests?.passed == 42 && checks.tests?.isCurrent == true && checks.filesChanged == 2)
    guard case .checks(let open)? = view("checks_open") else { Issue.record("checks_open"); return }
    #expect(open.unmet == 1 && open.isRepairable && open.requirements.first?.state == .open)

    guard case .review(let review)? = view("review") else { Issue.record("review"); return }
    #expect(review.decidedBy == .pebble && review.quote == "run the tests" && review.action == "tests")
    guard case .question(let question)? = view("question") else { Issue.record("question"); return }
    #expect(question.questions == 1 && question.state == .done)
}

@Test(.enabled(if: SpecFixtures.exists, "the spec's fixtures sit next to this repository")) func headerAndSummaryDecode() throws {
    let fixtures = try SpecFixtures.load()
    let header = try #require(WorkHeader(json: fixtures["header"]))
    #expect(header.state == "running" && header.elapsed == 72.4)
    let plan = try #require(header.plan)
    #expect(plan.total == 5 && plan.done == 2 && plan.current?.title == "Fix the refresh")

    let summary = try #require(WorkSummary(json: fixtures["summary"]))
    #expect(summary.files == WorkSummary.Files(count: 1, added: 4, removed: 2))
    #expect(summary.commands == WorkSummary.Commands(count: 2, failed: 1))
    #expect(summary.tests == WorkSummary.Tests(passed: 41, failed: 1))
    #expect(summary.checks == "A check asked for more evidence" && summary.seconds == 95.2)
    #expect(summary.tokens == WorkSummary.Tokens(input: 52310, cached: 28770, output: 3120))

    // Unknowns are null in the header and the summary: they stay nil, never zero.
    let empty = try #require(WorkHeader(json: ["plan": .null, "state": .null, "elapsed": .null]))
    #expect(empty.plan == nil && empty.state == nil && empty.elapsed == nil)
    #expect(WorkSummary(json: .null) == nil)
}

@Test(.enabled(if: SpecFixtures.exists, "the spec's fixtures sit next to this repository")) func everyNativeKindDecodes() throws {
    let native = try #require(try SpecFixtures.load()["native"]?.object)
    #expect(Set(native.keys) == Set(NativeView.kinds).subtracting(["html"]))
    for (kind, data) in native {
        let view = NativeView(kind: kind, data: data)
        #expect(view.isDrawn, "\(kind) should draw")
        switch (kind, view) {
        case ("form", .form(let form)):
            #expect(form.fields.count == 1 && form.fields[0].kind == .choice && form.fields[0].options.count == 2)
            #expect(form.submitLabel == "Continue")
        case ("table", .table(let table)):
            #expect(table.columns.map(\.id) == ["file", "lines"] && table.rows.count == 2)
            #expect(table.rows[0].cells == [.text("session.py"), .number(212)] && table.caption == "Files the fix touches")
        case ("chart", .chart(let chart)):
            #expect(chart.style == .bar && chart.rows.map(\.values) == [[4], [7], [5]] && chart.name(of: "runs") == "Runs")
        case ("plan", .plan(let plan)):
            #expect(plan.steps.map(\.status) == [.inProgress, .pending])
        case ("evidence", .evidence(let evidence)):
            #expect(evidence.items.first?.evidenceID == "3:call_tests")
        case ("quiz", .quiz(let quiz)):
            // The fixture carries the answer and the explanation; they are never read.
            #expect(quiz.durationMinutes == 5 && quiz.questions.first?.choices == ["3", "4"])
        case ("diagram", .diagram(let diagram)):
            #expect(diagram.nodes.count == 3 && diagram.edges.count == 2 && diagram.edges[0].label == "checks session")
        case ("dashboard", .dashboard(let dashboard)):
            #expect(dashboard.columns == 2 && dashboard.panels.count == 2 && dashboard.liveCount == 0)
            guard case .ready(.metric(let metric)) = dashboard.panels[0].state else {
                Issue.record("the metric panel")
                continue
            }
            #expect(metric.value == 16 && metric.delta == 3 && metric.unit == "runs")
        case ("prototype", .prototype(let prototype)):
            #expect(prototype.start == "home" && prototype.screens.count == 2)
            #expect(prototype.screen("home")?.components.last == .button(.init(label: "Settings", target: "settings")))
        default:
            Issue.record("\(kind) decoded as \(view)")
        }
    }
    #expect(NativeView(kind: "html", data: ["html": "<p>x</p>"]) == .macOnly)
    #expect(NativeView(kind: "hologram", data: ["trees": 3]) == .unsupported)
    #expect(NativeView(kind: "chart", data: ["type": "bar", "x_key": "day", "y_keys": ["runs"], "rows": [["day": "Mon", "runs": "four"]]]) == .unsupported)
}

@Test func viewsEnforceTheBounds() {
    let long = String(repeating: "a", count: 450)
    let tail: [JSONValue] = (1...12).map { .string("line \($0)") }
    let view = WorkView(json: [
        "v": 1, "type": "command", "command": .string(long), "tail": .array(tail), "exit": "zero", "seconds": -1,
        "where": "Project\u{0007} folder\u{202E}", "brand_new_field": true,
    ])
    guard case .command(let command)? = view?.content else {
        Issue.record("a command with bad fields must still draw")
        return
    }
    #expect(command.command?.count == 400 && command.command?.hasSuffix("\u{2026}") == true)
    #expect(command.tail.count == 8 && command.tail.first == "line 1")
    #expect(command.exit == nil && command.seconds == nil)  // a field that fails its check is left out
    #expect(command.place == "Project folder")  // controls become spaces, runs collapse, ends trimmed

    #expect(WorkView(json: ["v": 2, "type": "read"]) == nil)
    #expect(WorkView(json: ["type": "read"]) == nil)
    #expect(WorkView(json: ["v": 1]) == nil)
    #expect(WorkView(json: .array([])) == nil)
    #expect(WorkView(json: nil) == nil)
    #expect(WorkView(json: ["v": 1, "type": "read", "more": true])?.more == true)
    #expect(ViewText.clamp("  \n\t ", 10) == nil)
    #expect(ViewText.clamp("one\ntwo", 10, multiline: true) == "one\ntwo")
}

@Test(.enabled(if: SpecFixtures.exists, "the spec's fixtures sit next to this repository")) func itemsGroupIntoCardsAsOnTheMac() throws {
    let fixtures = try SpecFixtures.load()
    let items = (fixtures["summary_items"]?.array ?? []).compactMap { SpecItem(fixtures["items"]?[$0.string ?? ""]) }
    let entries = WorkEntries.group(items)
    let shape: [String] = entries.map { entry in
        switch entry {
        case .card(let card): "\(card.kind.rawValue)×\(card.items.count)"
        case .row(let item): "row:\(item.workView?.type ?? "text")"
        }
    }
    #expect(shape == [
        "explored×3", "web×1", "files×2", "command×1", "command×1", "tests×1", "git×1", "git×1", "window×2", "agents×1",
        "checks×1", "checks×1", "row:review", "row:review", "row:question", "row:text",
    ])
    guard case .card(let files) = entries[2] else { Issue.record("files"); return }
    #expect(files.fileChanges.count == 2 && files.diff.added == 6 && files.diff.removed == 2)
    guard case .card(let explored) = entries[0] else { Issue.record("explored"); return }
    #expect(explored.exploredCounts.reads == 2 && explored.exploredCounts.searches == 1)
}

@Test(.enabled(if: SpecFixtures.exists, "the spec's fixtures sit next to this repository")) func formArtifactsCarryTheirQuestion() throws {
    let form = try #require(try SpecFixtures.load()["native"]?["form"])
    let row: JSONValue = [
        "id": "a1", "chat_id": "c1", "title": "Scope", "kind": "form", "revision": 2, "status": "ready", "created": 1_761_900_000,
        "data": form,
        "form_question": ["id": "q1", "revision": 1, "status": "pending", "answer": .null],
    ]
    let artifact = try #require(PebbleArtifact(json: row))
    #expect(artifact.waitsForAnswer && artifact.revision == 2 && artifact.form?.fields.first?.id == "scope")
    var answered = row
    if case .object(var object) = answered {
        object["form_question"] = ["id": "q1", "revision": 1, "status": "answered", "answer": ["scope": ["option_id": "auth"]]]
        answered = .object(object)
    }
    let done = try #require(PebbleArtifact(json: answered))
    #expect(!done.waitsForAnswer && done.formQuestion?.answers["scope"] == .option("auth"))
    #expect(PebbleArtifact(json: ["kind": "form"]) == nil)
}

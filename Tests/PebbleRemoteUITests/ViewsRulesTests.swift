import Foundation
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Lane G: the rules behind Pebble's views on the phone. A form takes its answers only complete, a card's words come
/// from Pebble's window, and a view's card says what it can't show.
struct ViewsRulesTests {
    static let form: JSONValue = [
        "id": "a1", "chat_id": "c1", "title": "Ship it", "kind": "form", "revision": 1, "status": "ready",
        "data": [
            "fields": [
                ["id": "port", "label": "Which port?", "type": "choice", "options": [["id": "a", "label": "A"], ["id": "b", "label": "B"]]],
                ["id": "who", "label": "Who gets the link?", "type": "text"],
            ]
        ],
        "form_question": ["id": "q1", "revision": 1, "status": "pending"],
    ]

    static func item(_ seq: Int, _ view: JSONValue, status: String = "done") -> RunActivityItem {
        RunActivityItem(seq: seq, at: 1, kind: "tool", label: "Step", status: status, view: WorkView(json: view))
    }

    @Test func aFormTakesItsAnswersOnlyWhenComplete() throws {
        let artifact = try #require(PebbleArtifact(json: Self.form))
        let form = try #require(artifact.form)
        #expect(FormAnswers.make(form, choices: ["port": "a"], texts: [:]) == nil)
        #expect(FormAnswers.make(form, choices: ["port": "z"], texts: ["who": "Sam"]) == nil)  // not an option
        #expect(FormAnswers.make(form, choices: ["port": "a"], texts: ["who": "   "]) == nil)
        let answers = FormAnswers.make(form, choices: ["port": "b"], texts: ["who": "  Sam  "])
        #expect(answers == ["port": .option("b"), "who": .text("Sam")])
        #expect(FormAnswers.isOpen(artifact) && FormAnswers.state(artifact).words == AppCopy.Views.waitingForAnswers)
        let kept = FormAnswers.values(form, from: ["port": .option("b"), "who": .text("Sam")])
        #expect(kept.choices == ["port": "b"] && kept.texts == ["who": "Sam"])
    }

    @Test func aCardsWordsAreThoseOfPebblesWindow() throws {
        let failed = try #require(
            WorkCardWords.card(
                for: Self.item(
                    1, ["v": 1, "type": "command", "command": "npm run build", "state": "failed", "exit": 2, "seconds": 0.8],
                    status: "failed")))
        #expect(WorkCardWords.title(failed) == "npm run build")
        #expect(WorkCardWords.status(failed, runIsLive: false)?.words == "exit 2 \u{00B7} <1 s")
        #expect(WorkCardWords.status(failed, runIsLive: false)?.tone == .bad)

        let checks = try #require(
            WorkCardWords.card(for: Self.item(2, ["v": 1, "type": "checks", "unmet": 1, "requirements": [["text": "Tests pass", "state": "open"]]])))
        #expect(WorkCardWords.status(checks, runIsLive: false)?.words == AppCopy.Views.notAllMet)

        let running = try #require(WorkCardWords.card(for: Self.item(3, ["v": 1, "type": "read", "path": "a.py"], status: "running")))
        #expect(WorkCardWords.status(running, runIsLive: true)?.words == AppCopy.Views.inProgress)
        #expect(WorkCardWords.status(running, runIsLive: false)?.words == AppCopy.Views.unfinished)
        #expect(WorkCardWords.title(running) == "Read 1 file")

        // Review and question items stay rows: their real cards are drawn in place.
        #expect(WorkCardWords.card(for: Self.item(4, ["v": 1, "type": "review", "state": "waiting"])) == nil)
    }

    @Test func aViewsCardSaysWhatItCantShow() throws {
        let page = try #require(PebbleArtifact(json: ["id": "p", "chat_id": "c1", "kind": "html", "data": ["html": "x"]]))
        #expect(ViewCard.state(page)?.words == AppCopy.Views.onYourMac)
        let unknown = try #require(PebbleArtifact(json: ["id": "u", "chat_id": "c1", "kind": "timeline", "data": [:]]))
        #expect(ViewCard.state(unknown)?.words == AppCopy.Views.updateTheApp)
        let table = try #require(
            PebbleArtifact(json: ["id": "t", "chat_id": "c1", "kind": "table", "status": "stopped",
                                  "data": ["columns": [["id": "a", "label": "A"]], "rows": []]]))
        #expect(ViewCard.state(table)?.words == AppCopy.Views.stopped)
    }

    @Test func aDiagramIsLaidOutInLevelsEvenWithACycle() throws {
        guard case .diagram(let diagram) = NativeView(kind: "diagram", data: [
            "nodes": [["id": "a", "label": "A"], ["id": "b", "label": "B"], ["id": "c", "label": "C"]],
            "edges": [["from": "a", "to": "b", "label": "x"], ["from": "b", "to": "c", "label": "y"], ["from": "c", "to": "a", "label": "z"]],
        ]) else {
            Issue.record("the diagram should decode")
            return
        }
        // Every node is pointed to: the first starts the layout, and every node is placed once.
        let levels = DiagramLevels.levels(diagram)
        #expect(levels.flatMap { $0.map(\.id) }.sorted() == ["a", "b", "c"])
        #expect(levels.first?.map(\.id) == ["a"])
        #expect(DiagramLevels.lines(diagram).first == "A \u{2192} B: x")
    }

    @Test func aTableIsReadOutOneRowAtATimeWithItsColumnsNames() throws {
        let data: JSONValue = [
            "columns": [["id": "file", "label": "File"], ["id": "lines", "label": "Lines"]],
            "rows": [["file": "session.py", "lines": 212], ["file": "notes.md"]],
        ]
        guard case .table(let table) = NativeView(kind: "table", data: data) else {
            Issue.record("not a table")
            return
        }
        let spoken = table.rows.map { TableBody.spoken($0, columns: table.columns) }
        #expect(spoken == ["File: session.py, Lines: 212", "File: notes.md, Lines: \(AppCopy.Views.emptyCell)"])
    }
}

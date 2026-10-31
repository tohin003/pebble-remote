import Foundation
import PebbleProtocol

// Lane T (2026-10-31): the demo answers a view's history and Stop (app.py `artifact_history`, `artifact_stop`;
// artifact_inputs.py `stop`) and the export calls (exports.py) with Pebble's shapes and refusals, word for word.

extension DemoClient {
    /// The views' history and Stop, and the exports' calls but Create file (`renderExport`); nil for another method.
    func viewsAndExportsAnswer(_ method: String, _ params: JSONValue) throws -> JSONValue? {
        switch method {
        case "artifact_history":
            let (chat, row) = try currentView(params)
            return .array(exportsDemo.history(of: row, in: chat))
        case "artifact_stop":
            return try stopView(params)
        case "export_preview":
            return try previewExport(params)
        case "export_cancel":
            let plan = params["plan_id"]?.string ?? ""
            guard let chat = exportsDemo.rendering[plan], chat == params["chat_id"]?.string else { return false }
            exportsDemo.cancelled.insert(plan)
            return true
        case "export_discard":
            let (chat, index) = try exportRecord(params)
            guard case .object(var record)? = exportsDemo.records[chat]?[index] else {
                throw refusal("Export not found in this conversation.")
            }
            record["status"] = "discarded"
            record["file"] = .null
            exportsDemo.records[chat]?[index] = .object(record)
            return ["export_id": record["export_id"] ?? .null, "status": "discarded"]
        case "export_list":
            guard let chat = params["chat_id"]?.string, chatIndex(chat) != nil else {
                throw refusal("Conversation not found.")
            }
            let keep = [
                "export_id", "format", "status", "title", "source", "file", "failed_checks", "created", "published",
            ]
            return .array(
                (exportsDemo.records[chat] ?? []).prefix(50).map { row -> JSONValue in
                    .object((row.object ?? [:]).filter { keep.contains($0.key) })
                })
        case "export_get":
            let (chat, index) = try exportRecord(params)
            return exportsDemo.records[chat]?[index] ?? .null
        default:
            return nil
        }
    }

    // MARK: A view's history and Stop

    /// artifacts.py `get` with a revision: a positive number within the view's history.
    func viewRevision(_ params: JSONValue, _ revision: JSONValue) throws -> JSONValue {
        let (chat, row) = try currentView(params)
        guard let number = revision.int, number >= 1, case .int = revision else {
            throw refusal("Use a positive integer artifact revision.")
        }
        let history = exportsDemo.history(of: row, in: chat)
        guard number <= history.count else { throw refusal("Artifact revision not found.") }
        return history[number - 1]
    }

    private func currentView(_ params: JSONValue) throws -> (chat: String, row: JSONValue) {
        guard let chat = params["chat_id"]?.string, let id = params["id"]?.string, chatIndex(chat) != nil,
            let row = views.row(id, in: chat)
        else { throw refusal("Artifact not found.") }
        return (chat, row)
    }

    /// artifact_inputs.py `stop`: the current revision only; a stopped or expired view comes back as it is; otherwise
    /// a new revision, stopped, and a form's pending question is cancelled (a task that needs the answer stops).
    private func stopView(_ params: JSONValue) throws -> JSONValue {
        let (chat, row) = try currentView(params)
        let revision = row["revision"]?.int ?? 1
        guard params["revision"]?.int == revision else {
            throw refusal("This artifact revision is stale. Refresh before stopping.")
        }
        guard case .object(var object) = row, let id = object["id"]?.string else { return row }
        if ["stopped", "expired"].contains(object["status"]?.string ?? "") { return row }
        exportsDemo.earlier[chat + "/" + id] = Array(exportsDemo.history(of: row, in: chat))
        object["revision"] = .int(revision + 1)
        object["status"] = "stopped"
        object["updated"] = .double(now().timeIntervalSince1970)
        if case .object(var asked)? = object["form_question"], asked["status"]?.string == "pending",
            let questionID = asked["id"]?.string
        {
            cancelFormQuestion(questionID, in: chat)
            asked["status"] = "cancelled"
            object["form_question"] = .object(asked)
        }
        views.put(.object(object), in: chat)
        emit(
            "artifact",
            ["chat_id": .string(chat), "id": .string(id), "revision": .int(revision + 1), "status": "stopped"])
        return .object(object)
    }

    /// interaction.py `cancel_question_in`, as the demo's question_cancel does it.
    private func cancelFormQuestion(_ id: String, in chat: String) {
        guard let index = chatIndex(chat), let position = chats[index].questions.firstIndex(where: { $0.id == id })
        else {
            return
        }
        var question = chats[index].questions[position]
        guard question.status == "pending" else { return }
        question.status = "cancelled"
        chats[index].questions[position] = question
        emit(
            "question",
            [
                "chat_id": .string(chat), "question_id": .string(id), "run_id": .string(question.runID),
                "status": "cancelled",
                "required": .bool(question.required), "question": question.json,
            ])
        if question.required, runs[question.runID]?.state == "waiting_input" { setState(question.runID, "stopped") }
    }

    // MARK: Exports

    /// exports.py `preview`: the format, the options, the view (the revision the person saw), and whether it fits.
    private func previewExport(_ params: JSONValue) throws -> JSONValue {
        guard let chat = params["chat_id"]?.string, chatIndex(chat) != nil else {
            throw refusal("Conversation not found.")
        }
        let format = params["format"]?.string ?? ""
        if format == "pptx" { throw refusal("Slide (PPTX) exports arrive in a later update.") }
        guard ExportFormat(rawValue: format) != nil else { throw refusal("Choose PDF, DOCX, XLSX, CSV or HTML.") }
        let options = params["options"]?.object ?? [:]
        guard Set(options.keys).isSubset(of: ["include_answers", "paper"]) else {
            throw refusal("Export options accept include_answers and paper only.")
        }
        let source = params["source"]
        guard source?["kind"]?.string == "artifact", let id = source?["id"]?.string, let row = views.row(id, in: chat)
        else {
            throw refusal("Choose a view, message, goal or run to export.")
        }
        let kind = row["kind"]?.string ?? ""
        if kind == "mcp_media" { throw refusal("Media views cannot be exported.") }
        let revision = row["revision"]?.int ?? 1
        if let asked = source?["revision"]?.int, asked != revision {
            throw refusal("This view changed to revision \(revision). Preview the export again.")
        }
        let tables = kind == "table" ? 1 : 0
        if format == "csv", tables != 1 {
            throw refusal("CSV holds exactly one table; this source has \(tables). Use XLSX instead.")
        }
        if format == "xlsx", tables == 0 { throw refusal("XLSX needs one to 32 tables; this source has 0.") }
        let plan = exportsDemo.nextID("p")
        let deadline = now().addingTimeInterval(600)
        exportsDemo.plans[plan] = DemoExports.Plan(
            chat: chat, format: format, viewID: id, revision: revision, title: row["title"]?.string ?? "View",
            kind: kind,
            deadline: deadline)
        return [
            "plan_id": .string(plan), "format": .string(format),
            "source": [
                "kind": "artifact", "id": .string(id), "revision": .int(revision),
                "digest": .string(DemoExports.digest(id)),
            ],
            "pages_estimate": 1, "deadline": .double(deadline.timeIntervalSince1970),
        ]
    }

    /// exports.py `render`: the plan once, then about two seconds of work (Cancel stops it), then the readback.
    func renderExport(_ params: JSONValue) async throws -> JSONValue {
        guard let chat = params["chat_id"]?.string, let id = params["plan_id"]?.string,
            let plan = exportsDemo.plans[id], plan.chat == chat
        else { throw refusal("This export preview is no longer available. Preview it again.") }
        exportsDemo.plans[id] = nil
        guard plan.deadline > now() else { throw refusal("This export preview expired. Preview it again.") }
        exportsDemo.rendering[id] = chat
        defer { exportsDemo.rendering[id] = nil }
        try? await wait(2)  // paced: none in tests (pace 0)
        let exportID = exportsDemo.nextID("x")
        let at = now().timeIntervalSince1970
        let record: JSONValue
        if exportsDemo.cancelled.remove(id) != nil {
            record = DemoExports.record(
                id: exportID, chat: chat, format: plan.format, status: "cancelled", title: plan.title,
                viewID: plan.viewID,
                revision: plan.revision, at: at, checks: [], reason: "Cancelled. The partial file was removed.")
        } else {
            let checks = DemoExports.checks(for: plan.format)
            let passed = checks.allSatisfy { $0["passed"]?.bool == true }
            record = DemoExports.record(
                id: exportID, chat: chat, format: plan.format, status: passed ? "verified" : "unverified",
                title: plan.title,
                viewID: plan.viewID, revision: plan.revision, at: at, checks: checks)
        }
        exportsDemo.records[chat, default: []].insert(record, at: 0)
        guard case .object(var answer) = record else { return record }
        answer["saves"] = nil
        return .object(answer)
    }

    private func exportRecord(_ params: JSONValue) throws -> (chat: String, index: Int) {
        guard let chat = params["chat_id"]?.string,
            let index = exportsDemo.records[chat]?.firstIndex(where: { $0["export_id"] == params["export_id"] })
        else { throw refusal("Export not found in this conversation.") }
        return (chat, index)
    }
}

import Foundation
import PebbleProtocol

// Lane G (2026-10-31): the demo answers the views' calls as app.py does (`artifact_get`, `artifact_submit`,
// `artifact_refresh`), and "Deploy the preview build" asks with a Pebble form whenever the person sends it a message:
// the form waits in Reviews and in the conversation until it is answered.

extension DemoClient {
    /// The views' calls; nil for any other method.
    func viewsAnswer(_ method: String, _ params: JSONValue) throws -> JSONValue? {
        switch method {
        case "artifact_get":
            // Lane T: an earlier revision (DemoClient+Exports).
            if let revision = params["revision"], revision != .null { return try viewRevision(params, revision) }
            return try viewRow(params)
        case "artifact_submit":
            return try submitForm(params)
        case "artifact_refresh":
            let row = try viewRow(params)
            guard row["kind"]?.string == "dashboard" else {
                throw refusal("Only a dashboard with live panels can be refreshed.")
            }
            guard params["revision"]?.int == row["revision"]?.int else {
                throw refusal("This view is stale: it changed. Open the new revision.")
            }
            guard case .object(var object) = row, let chat = params["chat_id"]?.string else { return row }
            if case .array(var results)? = object["bindings"] {
                for index in results.indices {
                    guard case .object(var result) = results[index] else { continue }
                    result["as_of"] = .double(now().timeIntervalSince1970)
                    results[index] = .object(result)
                }
                object["bindings"] = .array(results)
            }
            views.put(.object(object), in: chat)
            return .object(object)
        default:
            return nil
        }
    }

    private func viewRow(_ params: JSONValue) throws -> JSONValue {
        guard let chat = params["chat_id"]?.string, let id = params["id"]?.string, chatIndex(chat) != nil,
            let row = views.row(id, in: chat)
        else { throw refusal("Artifact not found.") }
        return row
    }

    /// artifact_inputs.submit: the current, ready revision of a form whose question is pending; every field answered
    /// once, with an offered option or written words.
    private func submitForm(_ params: JSONValue) throws -> JSONValue {
        let row = try viewRow(params)
        guard let chat = params["chat_id"]?.string, let id = params["id"]?.string, row["kind"]?.string == "form",
            params["revision"]?.int == row["revision"]?.int, row["status"]?.string == "ready"
        else { throw refusal("This form is stale or stopped. Refresh it before answering.") }
        guard let questionID = row["form_question"]?["id"]?.string, let index = chatIndex(chat),
            let position = chats[index].questions.firstIndex(where: { $0.id == questionID })
        else { throw refusal("This artifact has no native input capability.") }
        var question = chats[index].questions[position]
        guard question.status == "pending" else { throw refusal("This question is no longer accepting answers.") }
        let fields = row["data"]?["fields"]?.array ?? []
        guard let answers = params["answers"]?.object,
            Set(answers.keys) == Set(fields.compactMap { $0["id"]?.string })
        else { throw refusal("Answer each requested question exactly once.") }
        var said: [String] = []
        for field in fields {
            guard let fieldID = field["id"]?.string, let given = answers[fieldID]?.object else { continue }
            if Set(given.keys) == ["option_id"], let optionID = given["option_id"]?.string {
                guard let option = field["options"]?.array?.first(where: { $0["id"]?.string == optionID }),
                    let label = option["label"]?.string
                else { throw refusal("Choose an offered option or use free text.") }
                said.append(label)
            } else if Set(given.keys) == ["text"], let text = given["text"]?.string {
                let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !words.isEmpty, words.count <= 2000 else { throw refusal("Enter nonempty text under 2000 characters.") }
                said.append(words)
            } else {
                throw refusal("Choose an option or enter free text.")
            }
        }
        question.status = "answered"
        question.answer = .object(answers)
        chats[index].questions[position] = question
        let words = said.joined(separator: "\n")
        storeMessage(chat: chat, role: "user", content: words, id: "answer-" + questionID)
        if case .object(var object) = row, case .object(var asked)? = object["form_question"] {
            asked["status"] = "answered"
            asked["answer"] = .object(answers)
            object["form_question"] = .object(asked)
            views.put(.object(object), in: chat)
        }
        let message: JSONValue = ["id": .string("answer-" + questionID), "role": "user", "content": .string(words)]
        emit(
            "question",
            [
                "chat_id": .string(chat), "question_id": .string(questionID), "run_id": .string(question.runID),
                "status": "answered", "message": message, "question": question.json,
            ])
        emit("artifact", ["chat_id": .string(chat), "id": .string(id), "revision": row["revision"] ?? 1, "status": "answered"])
        if runs[question.runID]?.state == "waiting_input" {
            start(.continued(text: Self.deployReply(said), seconds: 8.4), run: question.runID)
        }
        return ["question_id": .string(questionID), "run_id": .string(question.runID), "status": "answered", "message": message]
    }

    /// "Deploy the preview build", after a new message: Pebble reads, checks the ports, then asks with a form.
    func playDeployForm(_ run: String, chat: String) async throws {
        try await step(
            run, "Reading package.json", tool: "Read", seconds: 0.6,
            view: ["v": 1, "type": "read", "path": "package.json", "start": 1, "total": 64])
        try await step(
            run, "Checking which ports are free", tool: "Bash", seconds: 0.9,
            view: [
                "v": 1, "type": "command", "command": "lsof -nP -iTCP:4173 -sTCP:LISTEN", "where": "Project folder",
                "network": false, "state": "done", "exit": 0, "seconds": 0.9,
                "tail": ["COMMAND   PID USER   FD   TYPE", "node    48213 you    23u  IPv4  TCP *:4173 (LISTEN)"],
            ])
        guard let index = chatIndex(chat) else { return }
        let id = views.nextID()
        let questionID = "q-\(id)"
        let created = now()
        let question = DemoQuestion(
            id: questionID, runID: run, chatID: chat, revision: 1, required: true, status: "pending",
            items: DemoViews.questionItems(DemoViews.portFields), created: created)
        chats[index].questions.append(question)
        let asked = DemoViews.formQuestion(
            questionID, run: run, chat: chat, fields: DemoViews.portFields, status: "pending", answer: .null, at: created)
        let row = DemoViews.row(
            id, chat: chat, run: run, title: "Choose the preview's port", kind: "form", data: DemoViews.portForm, at: created,
            extra: ["form_question": asked])
        views.put(row, in: chat)
        setState(run, "waiting_input")
        // The event carries the published row and its question's id (app.py, UIRender), as Pebble sends it.
        if case .object(var event) = row {
            event["form_question"] = nil
            event["question_id"] = .string(questionID)
            event["required"] = true
            event["status"] = "awaiting_user_input"
            emit("artifact", .object(event))
        }
        emit(
            "question",
            [
                "chat_id": .string(chat), "run_id": .string(run), "question_id": .string(questionID), "status": "pending",
                "question": question.json,
            ])
    }

    /// Pebble's own timeline item for a step (C4 `activity {chat_id, run_id, item}`).
    func emitActivity(_ run: String, _ item: JSONValue) {
        guard let chat = runs[run]?.chatID else { return }
        emit("activity", ["chat_id": .string(chat), "run_id": .string(run), "item": item])
    }

    /// The run's plan from UpdatePlan, after `done` of the login fix's four steps (`plan {chat_id, run_id, revision,
    /// steps}`).
    func emitPlan(_ run: String, done: Int) {
        guard let chat = runs[run]?.chatID else { return }
        let steps = DemoViews.loginPlan(done: done)
        views.plans[run] = steps
        emit("plan", ["chat_id": .string(chat), "run_id": .string(run), "revision": .int(done + 1), "steps": steps])
    }

    static func deployReply(_ said: [String]) -> String {
        let port = said.first ?? "the port you chose"
        let people = said.dropFirst().first ?? "you"
        return """
            Thanks. In the demo there's no Mac behind me; with your Mac paired I'd start the preview on \(port) now, \
            leave the program on 4173 alone, and send the link to \(people).
            """
    }
}

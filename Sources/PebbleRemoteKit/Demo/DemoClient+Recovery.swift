import Foundation
import PebbleProtocol

// The demo Pebble's answers for finishing and recovering a task (lane R), with Pebble's own refusals: Undo of an
// edit (app.py `undo`), a held task's three decisions (controller.py `held`), the uncertain outcomes (app.py
// `run_readback`, runtime.py `reconcile`, `settle_readback`), a command (process_jobs.py, process_reviews.py), and a
// model handoff (app.py `model_handoff_*`). Nothing runs anywhere: the demo pretends, in Pebble's shapes.

extension DemoClient {
    // MARK: - Undo (the demo's edits only)

    func undo(_ params: JSONValue) throws -> JSONValue {
        if activeRun != nil { throw refusal("Wait for the current task to finish before undoing an edit.") }
        let chat = try chatID(params)
        guard let index = chatIndex(chat),
            let action = chats[index].actions.first(where: { $0.id == params["action_id"]?.string }),
            action.kind == "edit", action.status == "applied"
        else { throw refusal("Only applied file edits can be undone.") }
        updateAction(chat: chat, action: action.id) { card in
            card.status = "undone"
            if case .object(var payload) = card.payload {
                payload["undo"] = [
                    "undone_at": .double(now().timeIntervalSince1970), "verified": true, "scope": "local file only",
                ]
                card.payload = .object(payload)
            }
        }
        return true
    }

    // MARK: - A held task (controller.py `held`)

    func held(_ method: String, _ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard let index = chatIndex(chat) else { throw refusal("Conversation not found.") }
        if activeRun != nil { throw refusal("Wait for the current task to finish first.") }
        guard let runID = params["run_id"]?.string, let run = runs[runID], run.chatID == chat else {
            throw refusal("Run not found in this conversation.")
        }
        guard run.state == "verification_required" else { throw refusal("This task is not waiting on verification.") }
        switch method {
        case "run_held_accept":
            runs[runID]?.error = "You accepted this task as unverified."
            setState(runID, "completed")
            return ["run_id": .string(runID), "status": "completed", "verified": false, "origin": "human"]
        case "run_held_tests":
            guard let root = chats[index].workspace else { throw refusal("This task has no project folder to test.") }
            let card = DemoAction(
                id: "a-" + nextID(), chatID: chat, kind: "tests", status: "pending",
                payload: [
                    "recipe": "npm test", "root": .string(root),
                    "plan": [
                        "recipe": "npm test", "kind": "npm", "argv": ["npm", "test"], "cwd": "snapshot", "timeout": 300,
                        "output_limit": 1_048_576, "network": false,
                    ],
                ], created: now())
            chats[index].actions.append(card)
            setState(runID, "waiting_approval")
            emit("actions", ["chat_id": .string(chat), "actions": .array(chats[index].actions.map(\.json))])
            return ["run_id": .string(runID), "status": "waiting_approval", "action_id": .string(card.id)]
        default:
            // One more repair: the task resumes and, in the demo, finishes verified.
            setState(runID, "queued")
            start(.continued(text: DemoData.themeAfterFinish, seconds: 9.1), run: runID)
            return ["run_id": .string(runID), "status": "queued"]
        }
    }

    // MARK: - Uncertain outcomes (run_readback, run_reconcile)

    func readback(_ params: JSONValue) throws -> JSONValue {
        if activeRun != nil { throw refusal("Stop the active run before reading back its outcomes.") }
        let run = try ownRun(params)
        return ["items": .array(recovery.uncertain[run] ?? []), "authorization": "none"]
    }

    func reconcile(_ params: JSONValue) throws -> JSONValue {
        if activeRun != nil { throw refusal("Stop the active run before reconciling an outcome.") }
        let run = try ownRun(params)
        guard runs[run]?.state == "needs_reconciliation" else {
            throw refusal("This run has no uncertain outcome to reconcile.")
        }
        guard let call = params["call_id"]?.string,
            let index = recovery.uncertain[run]?.firstIndex(where: { $0["call_id"]?.string == call }),
            let item = recovery.uncertain[run]?[index]
        else { throw refusal("Uncertain tool not found in this run.") }
        let result: JSONValue
        if params["effect"]?.string == "readback" {
            let verdict = item["verdict"]?.string
            guard verdict == "occurred" || verdict == "not_occurred" else {
                throw refusal(
                    "Only a clean occurred or not_occurred readback can settle this tool. Inspect it and report the outcome instead.")
            }
            result = [
                "status": "readback_verified", "verified": true, "basis": item["basis"] ?? .null,
                "effect": verdict == "occurred" ? "occurred" : "did_not_occur",
            ]
        } else {
            let effect = params["effect"]?.string ?? ""
            let note = (params["note"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["occurred", "did_not_occur"].contains(effect), !note.isEmpty, note.count <= 2000 else {
                throw refusal("Report occurred or did_not_occur with a note under 2000 characters.")
            }
            result = ["status": "user_reported", "effect": .string(effect), "note": .string(note), "verified": false]
        }
        recovery.uncertain[run]?.remove(at: index)
        if recovery.uncertain[run]?.isEmpty ?? true {
            // Nothing uncertain is left: the task is paused, ready to resume (Pebble sends no event for it).
            runs[run]?.state = "paused"
            runs[run]?.updated = now()
        }
        return result
    }

    private func ownRun(_ params: JSONValue) throws -> String {
        let chat = try chatID(params)
        guard let run = params["run_id"]?.string, runs[run]?.chatID == chat else { throw refusal("Run not found.") }
        return run
    }

    // MARK: - Commands (process_jobs.py, process_reviews.py)

    func process(_ method: String, _ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard chatIndex(chat) != nil else { throw refusal("Conversation not found.") }
        if method == "process_list" {
            return .array(recovery.processes.filter { $0.chatID == chat }.reversed().map(\.json))
        }
        guard let id = params["process_id"]?.string,
            let index = recovery.processes.firstIndex(where: {
                $0.id == id && $0.chatID == chat && $0.runID == params["run_id"]?.string
            })
        else { throw refusal("Process not found in this run.") }
        let job = recovery.processes[index]
        switch method {
        case "process_terminal":
            return [
                "process_id": .string(id), "interactive": .bool(job.interactive), "live": .bool(job.isLive),
                "echo": job.interactive ? true : .null, "input_bytes": .int(job.typed.utf8.count), "owned": .bool(job.interactive),
                "authorization": "none",
            ]
        case "process_read":
            let after = max(0, params["after"]?.int ?? 0), limit = max(1, min(params["limit"]?.int ?? 4000, 65_536))
            let characters = Array(job.output)
            let start = min(after, characters.count), end = min(start + limit, characters.count)
            return [
                "process_id": .string(id), "state": .string(job.state),
                "untrusted_process_output": .string(String(characters[start..<end])), "next_after": .int(end),
                "more": .bool(end < characters.count), "output_complete": .bool(!job.isLive && !job.uncertain),
                "controls_removed": 0, "outcome_uncertain": .bool(job.uncertain),
            ]
        case "process_stop":
            guard job.isLive else {
                if job.state == "unknown" {
                    throw refusal(
                        "This process has no live control owner in this service, so nothing was signalled. Pebble never signals a recorded process ID. Its outcome is unknown; inspect the project before relying on it."
                    )
                }
                return ["process_id": .string(id), "state": .string(job.state), "stop": "already_settled"]
            }
            settle(process: index, output: "^C\n")
            return ["process_id": .string(id), "state": "stopped", "stop": "requested"]
        case "process_input_human":
            guard settings["permissions"]?["tools"]?["terminal"]?.bool != false else {
                throw refusal("Terminal access is disabled in Permissions.")
            }
            guard job.isLive, job.interactive else { throw refusal("This process is not waiting for input.") }
            let text = params["text"]?.string, key = params["key"]?.string
            guard (text == nil) != (key == nil) else { throw refusal("Send either text or one key.") }
            if let text {
                guard text.utf8.count <= 1024 else { throw refusal("Send at most 1 KB at a time.") }
                recovery.processes[index].typed += text
            } else if key == "enter" {
                let answer = job.typed.trimmingCharacters(in: .whitespaces).lowercased()
                recovery.processes[index].output += job.typed + "\n"
                    + (answer.hasPrefix("y")
                        ? "Opened http://localhost:5173/ in your default browser.\n"
                        : "Okay. The site keeps running at http://localhost:5173/.\n")
                recovery.processes[index].typed = ""
            } else if key == "ctrl_c" {
                settle(process: index, output: "^C\n")
            } else if key == "ctrl_d" {
                recovery.processes[index].output += "^D\n"
            } else {
                throw refusal("Choose a key Pebble can send.")
            }
            return ["process_id": .string(id), "accepted": true]
        case "process_inspect":
            let observation = params["observation"]?.string ?? ""
            guard ["effect_observed", "no_effect_observed", "still_uncertain"].contains(observation) else {
                throw refusal("Choose the observed effect or an explicitly uncertain inspection.")
            }
            let note = (params["note"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty, note.utf8.count <= 2000 else { throw refusal("Record an inspection note of at most 2000 bytes.") }
            guard job.uncertain else { throw refusal("Only an owned uncertain outcome can be acknowledged.") }
            recovery.processes[index].inspected = true
            return [
                "process_id": .string(id), "inspection_recorded": true, "authorization": "none", "completion_verified": false,
            ]
        default:  // process_dismiss
            guard !job.isLive else { throw refusal("Stop the process and wait for it to settle before dismissing it.") }
            guard !job.uncertain || job.inspected else {
                throw refusal("Record an inspection before dismissing an uncertain outcome.")
            }
            recovery.processes.remove(at: index)
            return ["process_id": .string(id), "dismissed": true]
        }
    }

    /// A command stops: its last output, its new state, and Pebble's `process` event.
    private func settle(process index: Int, output: String) {
        recovery.processes[index].output += output
        recovery.processes[index].state = "stopped"
        let job = recovery.processes[index]
        emit(
            "process",
            ["chat_id": .string(job.chatID), "run_id": .string(job.runID), "process_id": .string(job.id), "state": "stopped"])
    }

    // MARK: - A model handoff (app.py `model_handoff_*`)

    func handoff(_ method: String, _ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard let index = chatIndex(chat) else { throw refusal("Conversation not found.") }
        switch method {
        case "model_handoff_preview":
            guard let run = params["run_id"]?.string, runs[run]?.chatID == chat else { throw refusal("Run not found.") }
            guard let profile = params["profile_id"]?.string, ["chatgpt", "default-local"].contains(profile) else {
                throw refusal("Model profile not found.")
            }
            let source = "cloud:chatgpt"
            let destination = profile == "default-local" ? "device" : "cloud:chatgpt"
            let messages = chats[index].messages
            let users = messages.filter { $0.role == "user" }.count, replies = messages.count - users
            var counts: [String: JSONValue] = [:]
            if users > 0 { counts["user"] = [source: .int(users)] }
            if replies > 0 { counts["assistant"] = [source: .int(replies)] }
            let fingerprint = "d3m0handoff" + nextID()
            recovery.handoffs[fingerprint] = DemoRecovery.Handoff(chatID: chat, runID: run, profile: profile)
            return [
                "plan_fingerprint": .string(fingerprint), "source_class": .string(source),
                "destination_class": .string(destination), "destination_fingerprint_prefix": "d3m0f1ngerpr1nt0042",
                "counts": .object(counts), "send_count": .int(messages.count), "bytes": .int(messages.reduce(0) { $0 + $1.content.utf8.count }),
                "withheld_ids": [], "withheld_by_class": [:], "released_classes": [], "crosses_class": .bool(source != destination),
                "profile_id": .string(profile), "statement": "", "status": "previewed", "authorization": "none",
            ]
        case "model_handoff_approve":
            guard let fingerprint = params["plan_fingerprint"]?.string, var entry = recovery.handoffs[fingerprint],
                entry.chatID == chat
            else { throw refusal("Review the handoff again; this preview is no longer available. Nothing was sent.") }
            entry.approved = true
            recovery.handoffs[fingerprint] = entry
            return ["approved": true, "plan_fingerprint": .string(fingerprint), "authorization": "none"]
        default:  // model_handoff_start
            if activeRun != nil { throw refusal("Stop the current task before starting a handoff.") }
            guard let fingerprint = params["plan_fingerprint"]?.string, let entry = recovery.handoffs[fingerprint],
                entry.chatID == chat
            else { throw refusal("Review the handoff again; this preview is no longer available. Nothing was sent.") }
            guard entry.approved else {
                throw refusal("The reviewed model handoff was refused (not_approved). Nothing was sent.")
            }
            recovery.handoffs[fingerprint] = nil  // one start per approval
            let (_, events) = try workflows.selectModel(["profile_id": .string(entry.profile)], taskRunning: false)
            for event in events { emit(event.name, event.data) }
            // The new conversation holds the cleared messages, then Pebble's handoff message starts its run.
            var made = DemoChat(
                id: "c-" + nextID(), title: String(("Handoff: " + chats[index].title).prefix(54)),
                workspace: chats[index].workspace, updated: now())
            made.messages = chats[index].messages.map { message in
                DemoMessage(id: "m-" + nextID(), role: message.role, content: message.content, created: message.created)
            }
            chats.append(made)
            let sent = made.messages.count
            storeMessage(
                chat: made.id, role: "user",
                content:
                    "Continue the task from the conversation above. It was handed off from another model route after a reviewed handoff; history the person did not release is not included."
            )
            let run = "r-" + nextID()
            runs[run] = DemoRun(
                id: run, chatID: made.id, state: "queued", steps: 0, elapsed: 0, error: nil, created: now(), updated: now(),
                messageID: "m-" + nextID())
            setState(run, "queued")
            start(.handedOff, run: run)
            return [
                "chat_id": .string(made.id), "run_id": .string(run), "sent": .int(sent), "withheld": 0,
                "destination_class": .string(entry.profile == "default-local" ? "device" : "cloud:chatgpt"),
                "authorization": "none",
            ]
        }
    }

    /// The handoff's new run: it reads the conversation, then replies on the new model.
    func playHandedOff(_ run: String) async throws {
        try await wait(0.4)
        setState(run, "running")
        try await step(run, "Reading the conversation so far", tool: "Read", seconds: 0.7)
        try await stream(run, DemoData.handoffReply)
        finish(run, seconds: 5.4)
    }
}

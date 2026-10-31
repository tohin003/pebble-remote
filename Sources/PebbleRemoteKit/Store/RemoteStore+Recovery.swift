import Foundation
import PebbleProtocol

// Finishing and recovering a task from the phone (lane R): a task held for verification, Resume with new limits, the
// windows an uncertain step paused and its uncertain outcomes, Undo, "Always allow", a running command, and continuing
// on the new model. Calls and params are Pebble's window's own (read-only Pebble checkout: RunPanel.vue,
// ReconcilePanel.vue, ExecutionOutput.vue, ModelHandoff.vue; App.vue `decide`, `grantAndApprove`, `shellUndo`,
// `proposeGitUndo`, `changeModel`); Pebble's lambda routes take exactly their named params, and the phone never sends
// `surface` (the bridge writes it, finding F10). Each call returns once the store shows Pebble's answer; a failure
// becomes `notice` in Pebble's words and is rethrown, as everywhere in the store.
//
// Face ID: what loses work or widens access asks for it every time (`run_held_accept`, `undo`, `shell_undo`,
// `shell_grant_add`, `process_input_human`, `model_handoff_approve`; inventory finding F3). The rest go plain and ask
// only when the bridge lists the method in `welcome.elevated` or answers `proof_required` (`act`).

extension RemoteStore {
    // MARK: - A task held for verification ("Finish this task"; controller.py `held`)

    /// "Run the tests": Pebble proposes the task's tests as a card that waits for review. Pebble's window offers it
    /// only in a project (`TaskAttention.hasProject`).
    public func runHeldTests(_ task: TaskAttention) async throws {
        _ = try await act("run_held_tests", Self.runParams(task), reason: StoreWords.runTestsReason(task.chatTitle))
        await refreshChat(task.chatID)
    }

    /// "Ask Pebble to finish": the task resumes with one more repair.
    public func askPebbleToFinish(_ task: TaskAttention) async throws {
        _ = try await act("run_held_finish", Self.runParams(task), reason: StoreWords.finishTaskReason(task.chatTitle))
        await refreshChat(task.chatID)
    }

    /// "Accept as unverified": Pebble keeps the change without verification and records that the person decided. Asks
    /// for Face ID.
    public func acceptUnverified(_ task: TaskAttention) async throws {
        _ = try await act(
            "run_held_accept", Self.runParams(task), reason: StoreWords.acceptUnverifiedReason(task.chatTitle),
            elevate: true)
        await refreshChat(task.chatID)
    }

    // MARK: - Resume (RunPanel "Resume")

    /// Resumes a paused, stopped, interrupted, failed or limit-reached task. After "Reached this task's limit." the new
    /// "Step limit" and "Active seconds" go with it (Pebble's window sends `limits` only then; Pebble's first values
    /// when none are given).
    public func resume(_ task: TaskAttention, limits: RunLimits? = nil) async throws {
        var params: [String: JSONValue] = ["id": .string(task.chatID), "run_id": .string(task.runID)]
        if task.needsLimits { params["limits"] = (limits ?? .resumeDefaults).json }
        _ = try await act("run_resume", .object(params), reason: StoreWords.resumeReason(task.chatTitle))
        await refreshChat(task.chatID)
    }

    // MARK: - Paused windows (RunPanel `loadPaused`, `decidePaused`)

    /// Reads the windows a conversation's uncertain step paused (`screen_sessions`, those Pebble reports as
    /// "interrupted"), when the conversation has one. Quietly: a read a screen makes on its own never asks for Face ID.
    public func loadPausedWindows(in chat: ChatID) async {
        guard offers("screen_sessions"), readsQuietly,
            world.runs.values.contains(where: { $0.row.chatID == chat && $0.row.state == .needsReconciliation })
        else { return }
        guard let result = try? await client.call("screen_sessions", ["id": .string(chat)]) else { return }
        let paused = (result.array ?? []).compactMap { ScreenSession(json: $0, chatID: chat) }
            .filter { $0.state == "interrupted" }
        publish(world.setPausedWindows(paused, in: chat))
    }

    /// "Done": the person looked at the window and it looks right, so Pebble may use it again. The task's sentence then
    /// reads as checked ("Send a message to continue.").
    public func markWindowDone(_ window: ScreenSession) async throws {
        _ = try await answer("screen_handoff_done", ["session_id": .string(window.id)])
        if let task = world.taskAttention(for: window.chatID), task.needsCheck {
            publish(world.markWindowChecked(run: task.runID, in: window.chatID))
        }
        await reloadWindows(after: window)
    }

    /// "End access": Pebble stops using the window.
    public func endAccess(_ window: ScreenSession) async throws {
        _ = try await answer("screen_session_revoke", ["session_id": .string(window.id)])
        screenSessions.removeAll { $0.id == window.id }
        await reloadWindows(after: window)
    }

    private func reloadWindows(after window: ScreenSession) async {
        publish(world.setPausedWindows(world.pausedWindows[window.chatID]?.filter { $0.id != window.id } ?? [], in: window.chatID))
        await loadPausedWindows(in: window.chatID)
        if loadedLists.contains(.screenSessions) { requestList(.screenSessions) }
    }

    // MARK: - Uncertain outcomes (ReconcilePanel.vue)

    /// What Pebble's readback finds for a task's uncertain outcomes (`run_readback`: read-only, settles nothing). While
    /// another task runs Pebble reads them back once it ends, which is not a failure.
    public func readback(_ task: TaskAttention) async throws -> ReadbackPage {
        let result: JSONValue
        do {
            result = try await client.call("run_readback", Self.runParams(task))
        } catch RemoteCallError.refused(let refusal) where refusal.message.contains("Stop the active run") {
            return ReadbackPage(items: [], waitsForTask: true)
        } catch {
            throw report(error)
        }
        let items = (result["items"]?.array ?? []).compactMap {
            UncertainOutcome(json: $0, chatID: task.chatID, runID: task.runID)
        }
        return ReadbackPage(items: items)
    }

    /// "Settle from readback": Pebble reads the state back itself and settles the outcome. Nothing is retried.
    public func settleFromReadback(_ outcome: UncertainOutcome) async throws {
        _ = try await act(
            "run_reconcile", Self.reconcileParams(outcome, effect: "readback", note: ""),
            reason: StoreWords.settleReason(world.title(of: outcome.chatID)))
        await refreshChat(outcome.chatID)
    }

    /// "Record my report": the person's own report ("It happened" or "It did not happen", with what they checked),
    /// recorded as unverified.
    public func recordReport(_ outcome: UncertainOutcome, _ report: OutcomeReport, note: String) async throws {
        let words = note.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await act(
            "run_reconcile", Self.reconcileParams(outcome, effect: report.rawValue, note: words),
            reason: StoreWords.settleReason(world.title(of: outcome.chatID)))
        await refreshChat(outcome.chatID)
    }

    // MARK: - Undo (App.vue `decide(…, 'undo')`, `shellUndo`, `proposeGitUndo`)

    /// Undoes what Pebble did, as its window's four buttons do: an edit or a command (`undo`), a Shell command or file
    /// write (`shell_undo`), or a Git change (`git_plan_propose`: a new plan that waits for review). Each but the Git
    /// plan puts files back, so it asks for Face ID.
    @discardableResult
    public func undo(_ action: ActionRecord) async throws -> UndoResult {
        let chat = action.chatID
        switch action.undo {
        case .edit?, .command?:
            _ = try await act(
                "undo", ["id": .string(chat), "action_id": .string(action.actionID)],
                reason: StoreWords.undoReason(action.title), elevate: true)
            await refreshChat(chat)
            return action.undo == .edit ? .editUndone : .commandUndone
        case .change(let snapshot)?:
            let result = try await act(
                "shell_undo", ["snapshot_id": .string(snapshot)], reason: StoreWords.undoReason(action.title),
                elevate: true)
            return (result["failed"]?.array ?? []).isEmpty ? .changeUndone : .someChangesNotUndone
        case .gitPlan(let receipt)?:
            _ = try await act(
                "git_plan_propose", ["id": .string(chat), "operation": "undo", "receipt_id": .string(receipt)],
                reason: StoreWords.proposeUndoReason(action.title))
            await refreshChat(chat)
            return .undoPlanReady
        case nil:
            throw refusal(StoreWords.notOffered)
        }
    }

    // MARK: - Always allow (App.vue `grantAndApprove`)

    /// "Always allow": saves the hosts and folders the card names as always allowed, then approves the card once. Each
    /// grant widens what Pebble may do, so it asks for Face ID (one check covers a burst). A grant Pebble refuses is
    /// shown and the card is still approved once, as on the Mac; cancelling Face ID approves nothing.
    public func alwaysAllow(_ item: ReviewItem) async throws {
        do {
            for grant in item.alwaysAllowGrants {
                _ = try await client.callElevated(
                    "shell_grant_add", ["kind": .string(grant.kind), "value": .string(grant.value), "scope": "always"],
                    reason: StoreWords.alwaysAllowReason(item.title))
            }
        } catch RemoteCallError.cancelledByPerson {
            throw RemoteCallError.cancelledByPerson
        } catch {
            _ = report(error)
        }
        try await approve(item)
    }

    // MARK: - Commands (ExecutionOutput.vue)

    /// Shows a conversation's commands: read now, and again on Pebble's `process`, `run`, `idle` and `actions` events
    /// for it, as Pebble's window does. Quietly: a screen's own read never asks for Face ID.
    public func watchCommands(in chat: ChatID) {
        processChats.insert(chat)
        requestCommands(chat)
    }

    /// Reads a conversation's commands now (`process_list`).
    public func loadCommands(in chat: ChatID) async {
        guard offers("process_list"), let result = try? await client.call("process_list", ["id": .string(chat)]) else {
            return
        }
        publish(world.setProcesses((result.array ?? []).compactMap { ProcessJob(json: $0, chatID: chat) }, in: chat))
    }

    /// The bridge lets the phone read a command's terminal without Face ID, so "Type into the command" shows only when
    /// the command takes typing, as on the Mac. Otherwise it shows for every running command and checks on the tap.
    public var readsTerminalsQuietly: Bool {
        offers("process_terminal") && !(bridge?.elevated.contains("process_terminal") ?? false)
    }

    /// The same, read on a screen's own account: plain, never with Face ID, and nil when the bridge wants more.
    public func readTerminal(of job: ProcessJob) async -> ProcessTerminal? {
        guard readsTerminalsQuietly, readsQuietly,
            let result = try? await client.call("process_terminal", Self.processParams(job))
        else { return nil }
        return ProcessTerminal(json: result)
    }

    /// Whether a command takes typing now, and whether it waits at a password prompt (`process_terminal`).
    public func terminal(of job: ProcessJob) async throws -> ProcessTerminal {
        ProcessTerminal(
            json: try await act("process_terminal", Self.processParams(job), reason: StoreWords.typeIntoCommandReason))
    }

    /// "Stop command".
    public func stopCommand(_ job: ProcessJob) async throws {
        _ = try await act("process_stop", Self.processParams(job), reason: StoreWords.stopCommandReason)
        await refreshCommands(job.chatID)
    }

    /// "Send line": the person's line, then Enter (ExecutionOutput `send`). At a password prompt it goes to the
    /// command only, never shown or kept. Asks for Face ID.
    public func typeLine(_ text: String, into job: ProcessJob) async throws {
        guard !text.isEmpty else { return }
        try await input(["text": .string(text)], to: job)
        try await input(["key": .string(ProcessKey.enter.rawValue)], to: job)
    }

    /// "Send Ctrl-C" or "Send Ctrl-D". Asks for Face ID.
    public func sendKey(_ key: ProcessKey, to job: ProcessJob) async throws {
        try await input(["key": .string(key.rawValue)], to: job)
    }

    /// "Record my inspection": what the person observed, with their note. It lets Pebble go on with newly reviewed
    /// project actions; the command's effects stay unverified.
    public func recordInspection(of job: ProcessJob, _ observation: ProcessObservation, note: String) async throws {
        var params = Self.processFields(job)
        params["observation"] = .string(observation.rawValue)
        params["note"] = .string(note.trimmingCharacters(in: .whitespacesAndNewlines))
        let result = try await act("process_inspect", .object(params), reason: StoreWords.inspectCommandReason)
        if result["inspection_recorded"]?.bool == true { publish(world.markInspected(process: job.id, in: job.chatID)) }
        await refreshCommands(job.chatID)
    }

    /// "Read output" and "Next output page": a page of the command's saved output (`process_read`, 4,000 characters).
    public func readOutput(of job: ProcessJob, after: Int = 0) async throws -> ProcessOutput {
        var params = Self.processFields(job)
        params["after"] = .int(after)
        params["limit"] = 4000
        return ProcessOutput(json: try await answer("process_read", .object(params)), after: after)
    }

    /// "Forget saved command output" (`process_dismiss`), for a settled command.
    public func forgetOutput(of job: ProcessJob) async throws {
        _ = try await act("process_dismiss", Self.processParams(job), reason: StoreWords.forgetOutputReason)
        await refreshCommands(job.chatID)
    }

    /// Pebble's window reads a conversation's commands again on these events (ExecutionOutput `subscribe`).
    func commandsMayHaveChanged(_ event: PebbleEvent) {
        guard ["process", "run", "idle", "actions"].contains(event.name), let chat = event.data["chat_id"]?.string,
            processChats.contains(chat)
        else { return }
        requestCommands(chat)
    }

    /// Reads a conversation's commands again, coalescing requests that arrive while a read is under way.
    func requestCommands(_ chat: ChatID) {
        guard offers("process_list"), readsQuietly else { return }
        if processTasks[chat] != nil {
            processAgain.insert(chat)
            return
        }
        processTasks[chat] = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.processAgain.remove(chat)
                await self.loadCommands(in: chat)
            } while self.processAgain.contains(chat)
            self.processTasks[chat] = nil
        }
    }

    func refreshCommands(_ chat: ChatID) async {
        processChats.insert(chat)
        requestCommands(chat)
        await processTasks[chat]?.value
    }

    private func input(_ fields: [String: JSONValue], to job: ProcessJob) async throws {
        let params = Self.processFields(job).merging(fields) { _, new in new }
        _ = try await act("process_input_human", .object(params), reason: StoreWords.typeIntoCommandReason, elevate: true)
    }

    // MARK: - Continue with the new model (ModelHandoff.vue; App.vue `changeModel`)

    /// Changes the model from a conversation (its composer's model menu). As on the Mac, a task there that can't resume
    /// on the new model (paused, interrupted, failed, out of budget) is then offered "Continue with the new model".
    public func selectModel(_ id: String, from chat: ChatID) async throws {
        try await selectModel(id)
        publish(world.offerHandoff(in: chat))
    }

    /// What continuing would send (`model_handoff_preview`): counts, route classes and a fingerprint, never contents.
    public func previewHandoff(_ offer: HandoffOffer) async throws -> HandoffPlan {
        guard let profile = world.model?.profileID else { throw refusal(StoreWords.handoffNotPrepared) }
        let result = try await act(
            "model_handoff_preview",
            ["id": .string(offer.chatID), "run_id": .string(offer.runID), "profile_id": .string(profile)],
            reason: StoreWords.approveHandoffReason)
        guard let plan = HandoffPlan(json: result) else { throw refusal(StoreWords.handoffNotPrepared) }
        return plan
    }

    /// "Approve this handoff": approves exactly this plan. Asks for Face ID. Nothing is sent yet.
    public func approveHandoff(_ plan: HandoffPlan, for offer: HandoffOffer) async throws {
        let result = try await act(
            "model_handoff_approve", ["id": .string(offer.chatID), "plan_fingerprint": .string(plan.fingerprint)],
            reason: StoreWords.approveHandoffReason, elevate: true)
        guard result["approved"]?.bool == true, result["plan_fingerprint"]?.string == plan.fingerprint else {
            throw refusal(StoreWords.handoffNotApproved)
        }
    }

    /// "Start the new run": Pebble continues the conversation as a new run on the new model, in a new conversation,
    /// which this returns. A start is never repeated from the phone: after an unclear answer the person checks the
    /// conversation's tasks and reviews again.
    @discardableResult
    public func startHandoff(_ plan: HandoffPlan, for offer: HandoffOffer) async throws -> ChatID {
        let result = try await act(
            "model_handoff_start", ["id": .string(offer.chatID), "plan_fingerprint": .string(plan.fingerprint)],
            reason: StoreWords.startHandoffReason)
        guard let run = result["run_id"]?.string, !run.isEmpty else { throw refusal(StoreWords.handoffNoRun) }
        publish(world.dismissHandoff(in: offer.chatID))
        await refreshState()
        return result["chat_id"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? offer.chatID
    }

    /// "Not now": the offer goes away.
    public func dismissHandoff(in chat: ChatID) {
        publish(world.dismissHandoff(in: chat))
    }

    // MARK: - Helpers

    /// The phone may read now without asking for Face ID: in the demo, with a bridge that has no unlock, or while
    /// unlocked (C1). Reads a screen makes on its own wait until then.
    public var readsQuietly: Bool { isDemo || bridge?.unlockSeconds == nil || isUnlocked }

    static func runParams(_ task: TaskAttention) -> JSONValue {
        ["id": .string(task.chatID), "run_id": .string(task.runID)]
    }

    static func reconcileParams(_ outcome: UncertainOutcome, effect: String, note: String) -> JSONValue {
        [
            "id": .string(outcome.chatID), "run_id": .string(outcome.runID), "call_id": .string(outcome.callID),
            "effect": .string(effect), "note": .string(note),
        ]
    }

    static func processFields(_ job: ProcessJob) -> [String: JSONValue] {
        ["id": .string(job.chatID), "run_id": .string(job.runID), "process_id": .string(job.id)]
    }

    static func processParams(_ job: ProcessJob) -> JSONValue { .object(processFields(job)) }

    /// A refusal the store writes itself, shown once as `notice`.
    private func refusal(_ words: String) -> RemoteCallError {
        let failure = PersonFacingError(message: words)
        notice = failure
        return .refused(failure)
    }
}

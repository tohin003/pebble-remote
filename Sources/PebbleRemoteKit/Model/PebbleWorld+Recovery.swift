import Foundation
import PebbleProtocol

// Finishing and recovering a task (lane R): what the world knows of a conversation's commands, its "Continue with the
// new model" offer, the windows its uncertain step paused, and how those and its task show (RunPanel.vue, App.vue).

extension PebbleWorld {
    // MARK: - Changes

    /// `process_list`'s answer for a conversation.
    @discardableResult
    public mutating func setProcesses(_ jobs: [ProcessJob], in chat: ChatID) -> WorldChange {
        guard processes[chat] != jobs else { return WorldChange() }
        processes[chat] = jobs
        return Self.shown(chat)
    }

    /// `process {chat_id, run_id, process_id, state}`: a command's new state. Pebble's window reads the list again on it
    /// (ExecutionOutput), which the store does too; until then the row shows the new state.
    mutating func processEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let chat, let id = data["process_id"]?.string, let state = data["state"]?.string,
            let index = processes[chat]?.firstIndex(where: { $0.id == id })
        else { return WorldChange() }
        processes[chat]?[index].state = state
        return Self.shown(chat)
    }

    /// Pebble recorded the person's inspection of a command (process_inspect's answer).
    @discardableResult
    public mutating func markInspected(process: String, in chat: ChatID) -> WorldChange {
        guard let index = processes[chat]?.firstIndex(where: { $0.id == process }) else { return WorldChange() }
        processes[chat]?[index].inspectionRecorded = true
        return Self.shown(chat)
    }

    /// After the person changed the model in a conversation: Pebble's window offers to continue the conversation's
    /// newest paused, interrupted, failed or out-of-budget task on the new model, and otherwise offers nothing
    /// (App.vue `changeModel`).
    @discardableResult
    public mutating func offerHandoff(in chat: ChatID) -> WorldChange {
        let newest = runs.values.filter { $0.row.chatID == chat && HandoffOffer.states.contains($0.row.state) }
            .max(by: Self.olderFirst)
        let offer = newest.map { HandoffOffer(chatID: chat, runID: $0.row.id) }
        guard handoffOffers[chat] != offer else { return WorldChange() }
        handoffOffers[chat] = offer
        return Self.shown(chat)
    }

    /// "Not now", or the handoff started (the new run lives in a new conversation).
    @discardableResult
    public mutating func dismissHandoff(in chat: ChatID) -> WorldChange {
        guard handoffOffers.removeValue(forKey: chat) != nil else { return WorldChange() }
        return Self.shown(chat)
    }

    /// `screen_sessions {id}`'s windows in state "interrupted": the ones an uncertain step paused.
    @discardableResult
    public mutating func setPausedWindows(_ windows: [ScreenSession], in chat: ChatID) -> WorldChange {
        guard (pausedWindows[chat] ?? []) != windows else { return WorldChange() }
        pausedWindows[chat] = windows.isEmpty ? nil : windows
        var change = Self.shown(chat)
        change.waiting = true
        return change
    }

    /// The person pressed Done on a window the task paused: its sentence reads as checked (RunPanel F254).
    @discardableResult
    public mutating func markWindowChecked(run: RunID, in chat: ChatID) -> WorldChange {
        guard checkedRuns.insert(run).inserted else { return WorldChange() }
        var change = Self.shown(chat)
        change.waiting = true
        return change
    }

    static func shown(_ chat: ChatID) -> WorldChange {
        var change = WorldChange()
        change.transcripts.insert(chat)
        return change
    }

    // MARK: - What the screens show

    /// The conversation's current task (RunPanel `current`), when its state is one a person may need to act on:
    /// paused, stopped, interrupted, failed, out of budget, held for verification, or with an uncertain step.
    public func taskAttention(for chat: ChatID) -> TaskAttention? {
        let chatRuns = runs.values.filter { $0.row.chatID == chat }
        guard let current = Self.focusedRun(Array(chatRuns), questions: pendingQuestions(in: chat)),
            TaskAttention.tracked.contains(current.row.state)
        else { return nil }
        let note = PersonNote.filter(current.row.error)
        return TaskAttention(
            chatID: chat, chatTitle: title(of: chat), runID: current.row.id, state: current.row.state,
            note: note.isEmpty ? nil : note, hasProject: chats[chat]?.workspace != nil,
            updated: current.row.updated ?? current.row.created, windowChecked: checkedRuns.contains(current.row.id),
            pausedWindows: current.row.state == .needsReconciliation ? pausedWindows[chat] ?? [] : [])
    }

    /// The conversation's "Continue with the new model" offer, while it can be acted on: Pebble's window shows it only
    /// while no task runs and a model is in use (App.vue: `handoffFor`, `state.model.profile_id`, `!state.active`).
    public func handoffOffer(for chat: ChatID) -> HandoffOffer? {
        guard let offer = handoffOffers[chat], activeChat == nil, model?.profileID != nil,
            runs[offer.runID] != nil
        else { return nil }
        return offer
    }

    /// The conversation's commands, as Pebble last listed them.
    public func commands(in chat: ChatID) -> [ProcessJob] { processes[chat] ?? [] }

    /// Cards Pebble acted on that offer an Undo, and cards the person undid, oldest first.
    func earlierActions(in chat: ChatID) -> [ActionRecord] {
        (actions[chat] ?? []).compactMap { action -> ActionRecord? in
            let undo = UndoOffer(kind: action.kind, status: action.status, payload: action.payload)
            guard undo != nil || action.status == "undone" else { return nil }
            return ActionRecord(
                chatID: chat, actionID: action.id, kind: action.kind, status: action.status,
                title: CardWords.title(kind: action.kind, payload: action.payload),
                detail: CardWords.detail(kind: action.kind, payload: action.payload), created: action.created,
                payload: action.payload, undo: undo)
        }
        .sorted { ($0.created ?? .distantPast, $0.actionID) < ($1.created ?? .distantPast, $1.actionID) }
    }

    /// What the conversation shows under its messages, in Pebble's order (RunPanel under the conversation, then the
    /// drawer's commands): the task's state and decisions, the handoff offer, then the commands.
    func recoveryItems(for chat: ChatID) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        if let task = taskAttention(for: chat), task.showsInConversation { items.append(.task(task)) }
        if let offer = handoffOffer(for: chat) { items.append(.handoff(offer)) }
        for job in commands(in: chat) where job.showsInConversation { items.append(.command(job)) }
        return items
    }
}

import Foundation
import PebbleProtocol

// What the screens read, derived from PebbleWorld. Pure functions of the world value.

extension PebbleWorld {
    /// Pebble at a glance; nil until the first `state` arrives.
    public func overview() -> PebbleOverview? {
        guard let settings else { return nil }
        return PebbleOverview(
            version: version ?? "", modelName: model?.name, effort: model?.effort, efforts: model?.efforts ?? [],
            defaultEffort: model?.defaultEffort, mode: settings.mode ?? .ask,
            fastReplies: settings.fastReplies, stealth: settings.stealth, screenControl: settings.screenControl,
            modelOnline: model?.isOnline ?? true,
            localModelState: model.flatMap { $0.kind == "gguf" && $0.configured ? $0.state : nil })
    }

    /// Every switch in Pebble's settings; nil until the first `state` arrives.
    public func pebbleSettings() -> PebbleSettings? {
        settings.map { PebbleSettings(json: $0.raw) }
    }

    /// Projects Pebble already knows: the folders of its conversations, most recently used first.
    public func projects() -> [ProjectRef] {
        var latest: [String: (name: String, used: Date?)] = [:]
        for chat in chats.values where !chat.trashed {
            guard let path = chat.workspace, let name = chat.project else { continue }
            let used = [latest[path]?.used, chat.updated].compactMap { $0 }.max()
            latest[path] = (name, used)
        }
        return latest.map { ProjectRef(path: $0.key, name: $0.value.name, lastUsed: $0.value.used) }
            .sorted { left, right in
                let a = left.lastUsed ?? .distantPast
                let b = right.lastUsed ?? .distantPast
                return a == b ? left.path < right.path : a > b
            }
    }

    /// The model profile in use, and the efforts it offers (state().model).
    public func currentModel() -> (profileID: String?, efforts: [String], effort: String?) {
        (model?.profileID, model?.efforts ?? [], model?.effort)
    }

    /// The Mac; nil until the bridge says its name.
    public func macOverview() -> MacOverview? {
        guard let name = macName ?? mac.name else { return nil }
        return MacOverview(
            name: name, batteryPercent: mac.batteryPercent, charging: mac.charging, onPower: mac.onPower,
            keepAwake: mac.keepAwake ?? false, pebbleRunning: pebbleRunning)
    }

    /// Conversations, newest activity first.
    public func chatSummaries() -> [ChatSummary] {
        let runsByChat = Dictionary(grouping: runs.values.filter { $0.row.chatID != nil }, by: { $0.row.chatID! })
        return chats.values.filter { !$0.trashed }
            .sorted { left, right in
                let a = left.updated ?? .distantPast
                let b = right.updated ?? .distantPast
                return a == b ? left.id > right.id : a > b
            }
            .map { chat in
                let cards = pendingCards(in: chat.id)
                let asked = pendingQuestions(in: chat.id)
                let focused = Self.focusedRun(runsByChat[chat.id] ?? [], questions: asked)
                // A held or uncertain task waits too, as on the Reviews tab.
                let decision = taskAttention(for: chat.id)?.waitsForDecision == true ? 1 : 0
                return ChatSummary(
                    id: chat.id, title: title(of: chat.id), project: chat.project, updated: chat.updated,
                    status: status(of: focused, cards: cards.count, questions: asked.count),
                    waitingCount: cards.count + asked.count + decision)
            }
    }

    /// Runs that are working, or waiting for the person in a way Stop can end, newest first.
    public func liveRuns() -> [LiveRun] {
        runs.values.filter { ($0.row.state.isLive || $0.row.state.isWaitingForPerson) && $0.row.chatID != nil }
            .sorted { Self.olderFirst($1, $0) }
            .map(liveRun)
    }

    /// The run a conversation shows in its run bar: working, or waiting for the person.
    public func liveRun(for chat: ChatID) -> LiveRun? {
        let chatRuns = runs.values.filter { $0.row.chatID == chat }
        guard let focused = Self.focusedRun(Array(chatRuns), questions: pendingQuestions(in: chat)),
            focused.row.state.isLive || focused.row.state.isWaitingForPerson
        else { return nil }
        return liveRun(focused)
    }

    /// Every card, question and task decision waiting for the person, across conversations, oldest first.
    public func waitingItems() -> [WaitingItem] {
        var items: [(created: Date, key: String, item: WaitingItem)] = []
        for chat in chats.keys {
            for action in pendingCards(in: chat) {
                items.append((action.created ?? .distantPast, "r/" + action.id, .review(reviewItem(action, chat: chat))))
            }
            for question in pendingQuestions(in: chat) {
                items.append((question.created ?? .distantPast, "q/" + question.id, .question(questionCard(question, chat: chat))))
            }
            if let task = taskAttention(for: chat), task.waitsForDecision {
                items.append((task.updated ?? .distantPast, "t/" + task.runID, .task(task)))
            }
        }
        return items.sorted { $0.created == $1.created ? $0.key < $1.key : $0.created < $1.created }.map(\.item)
    }

    /// One conversation's rows, in order: each reply with its run's activity lines before it and its end line after
    /// it, the cards Pebble acted on that offer an Undo at the end of the turn they happened in, then the task's state
    /// and decisions, the handoff offer and the commands (PebbleWorld+Recovery), then whatever is waiting for the person.
    public func transcriptItems(for chat: ChatID) -> [TranscriptItem] {
        guard let timeline = timelines[chat] else { return [] }
        let messages = self.messages(in: chat, timeline: timeline)
        var items: [TranscriptItem] = []
        var placed = Set<RunID>()
        var earlier = earlierActions(in: chat)
        for message in messages {
            if message.role == .user, let sent = message.created {
                // A card from an earlier turn closes that turn, before the person's next message.
                while let first = earlier.first, (first.created ?? .distantPast) < sent {
                    items.append(.action(first))
                    earlier.removeFirst()
                }
            }
            let runID = message.role == .assistant ? message.runID : nil
            if let runID, !placed.contains(runID) { items += activityItems(runID) }
            items.append(.message(message))
            if let runID, !placed.contains(runID) {
                if let end = runEnd(runID) { items.append(end) }
                placed.insert(runID)
            }
        }
        // Runs with no reply: working now, or stopped before writing one.
        let chatRuns = runs.values.filter { $0.row.chatID == chat }.sorted(by: Self.olderFirst)
        for record in chatRuns where !placed.contains(record.row.id) {
            let lines = activityItems(record.row.id)
            guard !lines.isEmpty else { continue }
            items += lines
            if let end = runEnd(record.row.id) { items.append(end) }
            placed.insert(record.row.id)
        }
        // How the newest run ended, even when the phone saw nothing of it.
        if let newest = chatRuns.last, !placed.contains(newest.row.id), let end = runEnd(newest.row.id) {
            items.append(end)
        }
        items += earlier.map(TranscriptItem.action)
        items += recoveryItems(for: chat)
        let waiting = waitingItems(in: chat)
        for item in waiting {
            switch item {
            case .review(let review): items.append(.review(review))
            case .question(let card): items.append(.question(card))
            case .task: break  // already under the conversation, with the other task controls
            }
        }
        return items
    }

    /// Pebble's counts for the conversation's finished runs (RunCopy.endLine).
    public func runRecaps(for chat: ChatID) -> [RunID: RunRecap] {
        var recaps: [RunID: RunRecap] = [:]
        for record in runs.values where record.row.chatID == chat {
            if let counts = record.row.counts {
                recaps[record.row.id] = RunRecap(steps: counts.steps, retries: counts.retries, waitedSeconds: counts.waited)
            } else if let steps = record.row.steps {
                recaps[record.row.id] = RunRecap(steps: steps)
            }
        }
        return recaps
    }

    public func title(of chat: ChatID) -> String {
        let title = chats[chat]?.title ?? ""
        return title.isEmpty ? "New conversation" : title  // Pebble's own name for an untitled conversation
    }

    public func project(of chat: ChatID) -> String? { chats[chat]?.project }

    /// The conversation's project folder on the Mac; nil in Companion.
    public func workspace(of chat: ChatID) -> String? { chats[chat]?.workspace }

    public func hasOlder(in chat: ChatID) -> Bool { timelines[chat]?.hasOlder ?? false }

    /// The conversation's run that is live now, if any (`send` then reaches it as guidance).
    public func isLive(chat: ChatID) -> Bool { liveRunID(in: chat).flatMap { runs[$0]?.row.state.isLive } ?? false }

    /// The pending card or question as the phone shows it, by ids.
    public func pendingCard(chat: ChatID, action: ActionID) -> ActionDTO? {
        actions[chat]?.first { $0.id == action && $0.isPending }
    }

    /// Runs Stop should end: the live one first (Pebble refuses to stop a waiting run in another conversation while
    /// one works), then the waiting ones.
    public func runsToStop() -> [(chat: ChatID, run: RunID, live: Bool)] {
        runs.values.filter { ($0.row.state.isLive || $0.row.state.isWaitingForPerson) && $0.row.chatID != nil }
            .sorted { left, right in
                left.row.state.isLive != right.row.state.isLive ? left.row.state.isLive : Self.olderFirst(right, left)
            }
            .map { ($0.row.chatID!, $0.row.id, $0.row.state.isLive) }
    }

    /// Conversations with a card or question waiting, or a run waiting for an approval or an answer: read again after
    /// a reconnect, so what waits is current (state() lists neither cards nor questions).
    public func chatsWithSomethingWaiting() -> Set<ChatID> {
        var result = Set<ChatID>()
        for (chat, list) in actions where list.contains(where: \.isPending) { result.insert(chat) }
        for (chat, list) in questions where list.contains(where: \.isPending) { result.insert(chat) }
        for record in runs.values where record.row.state == .waitingApproval || record.row.state == .waitingInput {
            if let chat = record.row.chatID, chats[chat] != nil { result.insert(chat) }
        }
        return result
    }

    /// The oldest message shown, where "load older" continues from.
    func firstStoredMessageID(in chat: ChatID) -> MessageID? { timelines[chat]?.stored.first?.id }

    // MARK: - Building blocks

    func pendingCards(in chat: ChatID) -> [ActionDTO] {
        (actions[chat] ?? []).filter(\.isPending)
    }

    func pendingQuestions(in chat: ChatID) -> [QuestionDTO] {
        (questions[chat] ?? []).filter(\.isPending)
    }

    func waitingItems(in chat: ChatID) -> [WaitingItem] {
        var items: [(created: Date, key: String, item: WaitingItem)] = []
        for action in pendingCards(in: chat) {
            items.append((action.created ?? .distantPast, "r/" + action.id, .review(reviewItem(action, chat: chat))))
        }
        for question in pendingQuestions(in: chat) {
            items.append((question.created ?? .distantPast, "q/" + question.id, .question(questionCard(question, chat: chat))))
        }
        return items.sorted { $0.created == $1.created ? $0.key < $1.key : $0.created < $1.created }.map(\.item)
    }

    /// Pebble's stored messages, then this phone's unsent-yet-unstored messages and the replies streaming in, in the
    /// order they appeared.
    func messages(in chat: ChatID, timeline: Timeline) -> [MessageItem] {
        let storedIDs = Set(timeline.stored.map(\.id))
        var extras: [(sequence: Int, item: MessageItem)] = timeline.local.map { ($0.sequence, $0.item) }
        for stream in streams.values where stream.chatID == chat && !storedIDs.contains(stream.messageID) {
            let item = MessageItem(
                id: stream.messageID, role: .assistant, text: stream.text, created: stream.created,
                isStreaming: !stream.finished, runID: stream.runID)
            extras.append((stream.sequence, item))
        }
        return timeline.stored + extras.sorted { $0.sequence < $1.sequence }.map(\.item)
    }

    /// A run's lines: Pebble's own timeline items when it sent them (C4), else the lines made from progress events.
    func activityItems(_ run: RunID) -> [TranscriptItem] {
        if let items = hostActivity[run], !items.isEmpty {
            return items.values.sorted { $0.seq < $1.seq }.map { item in
                .activity(id: "\(run)/h\(item.seq)", runID: run, text: item.label, status: hostStatus(item, run: run))
            }
        }
        return (activity[run] ?? []).map { .activity(id: $0.id, runID: run, text: $0.text, status: $0.status) }
    }

    /// A timeline item's status key: Pebble's class when it sent one, else its kind (a tool borrows the class of the
    /// progress line with the same label); never built from the label's words.
    func hostStatus(_ item: RunActivityItem, run: RunID) -> StatusKey {
        if let key = item.activity { return key }
        if item.status == "failed" { return .blocked }
        switch item.kind {
        case "tool":
            return activity[run]?.last { $0.text == item.label && $0.tool != nil }?.status ?? .working
        case "context", "model", "reasoning": return .thinking
        case "retry": return .reconnecting
        case "approval": return .review
        case "child": return .delegating
        case "check": return .testing
        default: return .working
        }
    }

    /// A run's end line: settled, or held for the person's decision. Its note keeps only the sentences meant for the
    /// person (PersonNote).
    func runEnd(_ run: RunID) -> TranscriptItem? {
        guard let record = runs[run] else { return nil }
        let state = record.row.state
        guard state.isSettled || [.budgetExhausted, .verificationRequired, .needsReconciliation].contains(state) else {
            return nil
        }
        let note = PersonNote.filter(record.row.error)
        return .runEnd(
            id: "end-\(run)", runID: run, state: state, seconds: record.row.elapsed ?? record.replySeconds,
            note: note.isEmpty ? nil : note)
    }

    func liveRun(_ record: RunRecord) -> LiveRun {
        let chat = record.row.chatID ?? ""
        let state = record.row.state
        let key =
            status(of: record, cards: pendingCards(in: chat).count, questions: pendingQuestions(in: chat).count)
            ?? state.statusKey ?? .working
        return LiveRun(
            id: record.row.id, chatID: chat, chatTitle: title(of: chat), state: state, status: key, activity: record.label,
            started: state.isLive ? record.liveSince : nil, steps: record.row.steps,
            attempt: state == .retryWait ? record.attempt : nil)
    }

    func reviewItem(_ action: ActionDTO, chat: ChatID) -> ReviewItem {
        ReviewItem(
            chatID: chat, chatTitle: title(of: chat), actionID: action.id, kind: action.kind,
            title: CardWords.title(kind: action.kind, payload: action.payload),
            detail: CardWords.detail(kind: action.kind, payload: action.payload), created: action.created,
            isSimple: action.kind.isSimple, payload: action.payload,
            summary: CardWords.summary(kind: action.kind, payload: action.payload),
            approveLabel: CardWords.approveLabel(kind: action.kind, payload: action.payload))
    }

    func questionCard(_ question: QuestionDTO, chat: ChatID) -> QuestionCard {
        var card = QuestionCard(
            chatID: chat, chatTitle: title(of: chat), questionID: question.id, runID: question.runID,
            revision: question.revision, required: question.required,
            prompts: question.items.map { item in
                QuestionCard.Prompt(
                    id: item.id, title: item.title,
                    options: item.options.map { .init(id: $0.id, label: $0.label, detail: $0.description) },
                    allowsFreeText: item.allowFreeText)
            },
            created: question.created, requester: question.requesterName)
        card.form = formArtifact(asking: question.id, in: chat)  // lane G
        return card
    }

    /// app.py chat()'s focus: the live run, else one with a pending question, else one waiting for approval, else the
    /// newest.
    static func focusedRun(_ chatRuns: [RunRecord], questions: [QuestionDTO]) -> RunRecord? {
        let newestFirst = chatRuns.sorted { olderFirst($1, $0) }
        let asked = Set(questions.compactMap(\.runID))
        return newestFirst.first { $0.row.state.isLive }
            ?? newestFirst.first { asked.contains($0.row.id) }
            ?? newestFirst.first { $0.row.state == .waitingApproval }
            ?? newestFirst.first
    }

    /// companionState.ts `choose()`, per conversation: a check needed, a problem, a card, a question, reconnecting,
    /// blocked, then what the live run does (its tool, writing, loading the model, thinking), then paused.
    func status(of record: RunRecord?, cards: Int, questions: Int) -> StatusKey? {
        let state = record?.row.state
        if state == .needsReconciliation { return .uncertain }
        if state == .failed { return .error }
        if cards > 0 || state == .waitingApproval { return .review }
        if questions > 0 || state == .waitingInput { return .question }
        if state == .retryWait { return .reconnecting }
        if state == .budgetExhausted || state == .verificationRequired { return .blocked }
        if let record, record.row.state.isLive {
            if let tool = record.tool { return tool }
            if record.writing { return .writing }
            if model?.isLoading == true { return .loading }
            return .thinking
        }
        if state == .paused { return .paused }
        return nil
    }
}

/// Pebble's run notes are written partly for the model ("Do not claim ...", "ScreenAct focus on its Address row"); the
/// person sees only the sentences meant for them. Ported from RunPanel.vue / PetRunSummary.vue `personNote`.
public enum PersonNote {
    static let forTheModel = ["Do not", "Don't", "Never", "Say ", "Tell the person", "Check the", "Otherwise"]
    static let toolNames = [
        "ScreenAct", "ScreenObserve", "ScreenRequest", "BrowserRequest", "OpenURL", "OpenApp", "AppAction", "RunTests",
        "RunCode", "ReadFile", "WriteFile", "EditFile", "Shell",
    ]

    public static func filter(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        return sentences(text)
            .filter { sentence in
                !forTheModel.contains(where: sentence.hasPrefix) && !toolNames.contains { mentions(sentence, $0) }
            }
            .joined(separator: " ")
    }

    /// Split on whitespace that follows a full stop, the stop staying with its sentence (JS /(?<=\.)\s+/).
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character?
        var skipping = false
        for character in text {
            if character.isWhitespace && (previous == "." || skipping) {
                if !skipping {
                    result.append(current)
                    current = ""
                    skipping = true
                }
                previous = character
                continue
            }
            skipping = false
            current.append(character)
            previous = character
        }
        result.append(current)
        return result
    }

    /// `name` as a whole word (JS \b...\b: ASCII word characters only).
    static func mentions(_ sentence: String, _ name: String) -> Bool {
        var searchStart = sentence.startIndex
        while let range = sentence.range(of: name, range: searchStart..<sentence.endIndex) {
            let before = range.lowerBound > sentence.startIndex ? sentence[sentence.index(before: range.lowerBound)] : nil
            let after = range.upperBound < sentence.endIndex ? sentence[range.upperBound] : nil
            if !isWordCharacter(before) && !isWordCharacter(after) { return true }
            searchStart = range.upperBound
        }
        return false
    }

    static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character == "_" || (character.isASCII && (character.isLetter || character.isNumber))
    }
}

extension PebbleWorld {
    /// The six memory layers: Pebble's own names and counts when `state` carried them, else its known names; each on
    /// unless Pebble's settings say otherwise.
    public func memoryLayers() -> [MemoryLayer] {
        let switches = pebbleSettings()?.memoryLayers ?? [:]
        let reported: [String: JSONValue] = Dictionary(
            memoryTypes.compactMap { type in type["id"]?.string.map { ($0, type) } }, uniquingKeysWith: { first, _ in first })
        return MemoryLayer.pebbleNames.map { layer in
            let type = reported[layer.id]
            return MemoryLayer(
                id: layer.id, name: type?["name"]?.string ?? layer.name, count: type?["count"]?.int,
                isOn: switches[layer.id] ?? true)
        }
    }
}

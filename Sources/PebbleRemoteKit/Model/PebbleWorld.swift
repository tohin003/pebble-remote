import Foundation
import PebbleProtocol

/// Everything the phone knows about Pebble, folded from `state`, conversations and events. A value type whose methods
/// are pure and deterministic: times come from the events and payloads, never from the clock, so the reducer is
/// tested event by event. RemoteStore keeps one and republishes only what each change touched (`WorldChange`).
///
/// It follows Pebble's own windows (read-only Pebble checkout): App.vue `receive()` for events, runEvents.ts for
/// questions and runs, companionState.ts for status keys, activity.ts for activity lines.
public struct PebbleWorld: Sendable {
    // MARK: Pebble and the Mac

    public internal(set) var version: String?
    public internal(set) var model: ModelDTO?
    /// nil until the first `state` arrives.
    public internal(set) var settings: SettingsDTO?
    public internal(set) var macName: String?
    public internal(set) var mac: MacDTO = MacDTO(json: .object([:]))
    public internal(set) var pebbleRunning = true
    public internal(set) var banner: ReplyBanner?
    /// Notices from scheduled jobs not yet acknowledged.
    public internal(set) var jobNotices: [JobNotice] = []
    /// state().memory.types, as Pebble sent them.
    var memoryTypes: [JSONValue] = []

    // MARK: Conversations

    var chats: [ChatID: ChatDTO] = [:]
    var runs: [RunID: RunRecord] = [:]
    /// Every card per conversation, as Pebble's last `actions` event or get_chat listed them.
    var actions: [ChatID: [ActionDTO]] = [:]
    /// Pending questions per conversation.
    var questions: [ChatID: [QuestionDTO]] = [:]
    /// Pebble's one worker: the conversation and run that hold it (state().active, App.vue's rule on `run` events).
    var activeChat: ChatID?
    var activeRun: RunID?
    /// Activity lines per run, from progress events (activity.ts fallback rows).
    var activity: [RunID: [ActivityLine]] = [:]
    /// Pebble's own timeline items per run (C4 `activity` events), by seq; preferred over progress lines when present.
    var hostActivity: [RunID: [Int: RunActivityItem]] = [:]
    /// Lane G: each conversation's views (get_chat's `artifacts` and `artifact` events), oldest first.
    var artifacts: [ChatID: [PebbleArtifact]] = [:]
    /// Lane G: each run's plan from UpdatePlan (`plan` events), for the work view's header between reads.
    var plans: [RunID: WorkPlan] = [:]
    /// Conversations opened on the phone: their messages.
    var timelines: [ChatID: Timeline] = [:]
    /// Replies streaming in, by message id, until Pebble's stored copy replaces them.
    var streams: [MessageID: Stream] = [:]
    var sequence = 0

    // MARK: Finishing and recovering a task (PebbleWorld+Recovery)

    /// Commands per conversation, as `process_list` last listed them (newest first, Pebble's order).
    var processes: [ChatID: [ProcessJob]] = [:]
    /// "Continue with the new model" offers, per conversation.
    var handoffOffers: [ChatID: HandoffOffer] = [:]
    /// Windows an uncertain step paused, per conversation, as `screen_sessions` last listed them.
    var pausedWindows: [ChatID: [ScreenSession]] = [:]
    /// Runs whose paused window the person checked with Done.
    var checkedRuns: Set<RunID> = []

    public init() {}

    // MARK: - Internal records

    struct RunRecord: Sendable, Hashable {
        var row: RunDTO
        /// The class of the last `working` progress with a tool (companionState's `tool`); nil between tools.
        var tool: StatusKey?
        /// A reply token arrived after the last progress event.
        var writing = false
        var attempt: Int?
        /// When this live stretch started, less the active seconds before it (Pebble counts active time only).
        var liveSince: Date?
        /// The latest activity line.
        var label: String?
        /// The reply's seconds from `complete`, when Pebble reported no elapsed time.
        var replySeconds: Double?
        /// A `run` event settled it. A settlement known only from a read (`state`, get_chat) may be ahead of events
        /// still on their way, whose progress lines still count.
        var settledByEvent = false
    }

    struct ActivityLine: Sendable, Hashable {
        var number: Int
        var runID: RunID
        var text: String
        var status: StatusKey
        /// A tool's line until its `done` event; a phase line until the run moves on.
        var running: Bool
        var tool: String?
        var id: String { "\(runID)/\(number)" }
    }

    struct Timeline: Sendable, Hashable {
        /// Pebble's stored messages, in Pebble's order.
        var stored: [MessageItem] = []
        /// The person's messages sent from this phone and not yet seen stored.
        var local: [LocalMessage] = []
        var hasOlder = false
    }

    struct LocalMessage: Sendable, Hashable {
        var item: MessageItem
        var sequence: Int
    }

    struct Stream: Sendable, Hashable {
        var chatID: ChatID
        var messageID: MessageID
        var runID: RunID?
        var text: String
        var created: Date?
        var finished: Bool
        var sequence: Int
    }

    static let labelLimit = 80
    static let linesPerRun = 200
    static let runsWithLines = 48

    // MARK: - Events

    /// Folds one event in. Unknown events change nothing.
    @discardableResult
    public mutating func apply(_ event: PebbleEvent) -> WorldChange {
        let data = event.data
        let chat = data["chat_id"]?.string
        // Pebble's bridge sends an event over 1 MB, or nested too deeply for the phone, as its ids and `trimmed: true`
        // (remote_bridge.py `publish`; contract 3.9). What it carried is read from Pebble instead.
        if data["trimmed"]?.bool == true { return Self.trimmed(chat: chat) }
        switch event.name {
        case "token": return token(chat: chat, data: data, time: event.time)
        case "progress": return progress(chat: chat, data: data, time: event.time)
        case "run": return runEvent(chat: chat, data: data, time: event.time)
        case "actions": return actionsEvent(chat: chat, data: data)
        case "question": return questionEvent(chat: chat, data: data)
        case "complete": return finishReply(chat: chat, data: data, refetchIfUnseen: true)
        case "stopped": return finishReply(chat: chat, data: data, refetchIfUnseen: false)
        case "idle": return idle(chat: chat, data: data)
        case "error": return errorEvent(chat: chat, data: data)
        case "model":
            guard let model = ModelDTO(json: data) else { return WorldChange() }
            self.model = model
            return WorldChange(overview: true, chats: true, runs: true)
        case "settings", "trashed", "restored", "deleted":
            return WorldChange(needsState: true)
        case "job":
            return WorldChange(lists: [.schedules, .notifications])
        case "job_notification":
            return WorldChange(needsState: true, lists: [.schedules])
        case "toolbox":
            return WorldChange(lists: [.toolbox])
        case "browser":
            return WorldChange(lists: [.screenSessions])
        case "remote.devices":
            return WorldChange(lists: [.devices])
        case "activity":
            return hostActivityEvent(chat: chat, data: data)
        case "artifact":
            return artifactEvent(chat: chat, data: data)  // lane G
        case "plan":
            return planEvent(chat: chat, data: data)  // lane G
        case "process":
            return processEvent(chat: chat, data: data)
        case "storage":
            return storageEvent(data)
        case "reply_banner":
            guard let chat, let title = data["title"]?.string, !title.isEmpty else { return WorldChange() }
            banner = ReplyBanner(chatID: chat, runID: data["run_id"]?.string, title: title, body: data["body"]?.string ?? "")
            return WorldChange(banner: true)
        case "ready":
            pebbleRunning = true
            return WorldChange(overview: true, mac: true, needsState: true)
        case "offline":
            pebbleRunning = false
            return markLiveRunsInterrupted()
        case "remote.mac":
            mac.merge(MacDTO(json: data))
            return WorldChange(mac: true)
        case "remote.pebble":
            let running = data["running"]?.bool ?? pebbleRunning
            let wasRunning = pebbleRunning
            pebbleRunning = running
            if let version = data["version"]?.string { self.version = version }
            var change = running ? WorldChange(overview: true, mac: true) : markLiveRunsInterrupted()
            change.needsState = running && !wasRunning
            return change
        default:
            return WorldChange()
        }
    }

    /// An event the bridge trimmed to its ids (`{chat_id?, run_id?, id?, trimmed: true}`): nothing in it is applied (a
    /// trimmed `actions` would otherwise read as no cards); `state` is read again, and the conversation it names if it
    /// is open here.
    static func trimmed(chat: ChatID?) -> WorldChange {
        var change = WorldChange(needsState: true)
        if let chat { change.needsChats.insert(chat) }
        return change
    }

    /// `token {chat_id, id, text}`: a piece of the reply with message id `id`.
    mutating func token(chat: ChatID?, data: JSONValue, time: Date?) -> WorldChange {
        guard let chat, let id = data["id"]?.string, let text = data["text"]?.string else { return WorldChange() }
        var change = WorldChange()
        let runID = liveRunID(in: chat)
        if let runID, runs[runID]?.writing == false {
            runs[runID]?.writing = true
            change.runs = true
            change.chats = true
        }
        if let index = timelines[chat]?.stored.firstIndex(where: { $0.id == id }) {
            // A resumed run continues its stored reply (App.vue appends to the message it already shows). Once its
            // run has settled, Pebble's stored copy is whole: a late piece would repeat what it already holds.
            let owner = timelines[chat]?.stored[index].runID ?? runID
            guard owner.flatMap({ runs[$0]?.row.state.isLive }) ?? (runID != nil) else { return change }
            timelines[chat]?.stored[index].text += text
            timelines[chat]?.stored[index].isStreaming = true
            if timelines[chat]?.stored[index].runID == nil { timelines[chat]?.stored[index].runID = runID }
        } else if streams[id] != nil {
            streams[id]?.text += text
            streams[id]?.finished = false
        } else {
            streams[id] = Stream(
                chatID: chat, messageID: id, runID: runID, text: text, created: time, finished: false,
                sequence: nextSequence())
        }
        if timelines[chat] != nil { change.transcripts.insert(chat) }
        return change
    }

    /// `progress {chat_id, run_id, label, kind, activity, tool?, attempt?}`: what the run is doing. The status comes
    /// from `activity` (or the tool's class), never from `label`; the label becomes an activity line.
    mutating func progress(chat: ChatID?, data: JSONValue, time: Date?) -> WorldChange {
        guard let chat, let runID = data["run_id"]?.string ?? liveRunID(in: chat) else { return WorldChange() }
        var change = WorldChange()
        if runs[runID] == nil {
            // First seen through its progress (the phone connected mid-run): live until Pebble says otherwise.
            runs[runID] = RunRecord(row: RunDTO(id: runID, chatID: chat, state: .running, created: time), liveSince: time)
            activeChat = chat
            activeRun = runID
            change.runs = true
            change.chats = true
        }
        guard var record = runs[runID] else { return change }
        let kind = data["kind"]?.string ?? ""
        let tool = data["tool"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        guard record.row.state.isLive else {
            // Settled: no status changes. Pebble's window ignores progress once a run settles; a settlement read
            // from `state` may be ahead of these events, though, so their lines still count until the event says so.
            guard !record.settledByEvent, let label = Self.clean(data["label"]?.string, limit: Self.labelLimit),
                addActivityLine(runID: runID, label: label, kind: kind, tool: tool, data: data)
            else { return change }
            if timelines[chat] != nil { change.transcripts.insert(chat) }
            return change
        }
        let before = record
        if kind == "working", let tool {
            record.tool = Self.toolStatus(activity: data["activity"]?.string, tool: tool)
        } else {
            record.tool = nil
        }
        record.writing = false
        if let attempt = data["attempt"]?.int, (1...99).contains(attempt) { record.attempt = attempt }
        let label = Self.clean(data["label"]?.string, limit: Self.labelLimit)
        if let label { record.label = label }
        runs[runID] = record
        if record != before {
            change.runs = true
            change.chats = true
        }
        if let label, addActivityLine(runID: runID, label: label, kind: kind, tool: tool, data: data) {
            if timelines[chat] != nil { change.transcripts.insert(chat) }
        }
        return change
    }

    /// companionState: Pebble's own class wins over the phone's table; "thinking" shows no tool; anything else that
    /// is not a tool class is plain working.
    static func toolStatus(activity: String?, tool: String) -> StatusKey? {
        let key = activity ?? StatusKey.forTool(tool).rawValue
        if let status = StatusKey(rawValue: key), status.isToolClass { return status }
        return key == StatusKey.thinking.rawValue ? nil : .working
    }

    /// activity.ts `fallback`: a tool's `done` closes its own line; anything else adds one and ends a phase line.
    mutating func addActivityLine(runID: RunID, label: String, kind: String, tool: String?, data: JSONValue) -> Bool {
        var lines = activity[runID] ?? []
        if kind == "done", tool != nil,
            let index = lines.lastIndex(where: { $0.running && $0.text == label && $0.tool != nil })
        {
            lines[index].running = false
            activity[runID] = lines
            return true
        }
        for index in lines.indices where lines[index].running && lines[index].tool == nil {
            lines[index].running = false  // a new step ends the previous phase line
        }
        let attempt = data["attempt"]?.int.flatMap { (1...99).contains($0) ? $0 : nil }
        let text = attempt.map { Self.clean("\(label) (attempt \($0))", limit: Self.labelLimit) ?? label } ?? label
        let status: StatusKey
        if attempt != nil {
            status = .reconnecting
        } else {
            switch kind {
            case "working": status = tool.map { Self.toolStatus(activity: data["activity"]?.string, tool: $0) ?? .thinking } ?? .thinking
            case "review": status = .review
            case "blocked": status = .blocked
            case "done": status = tool.map { Self.toolStatus(activity: data["activity"]?.string, tool: $0) ?? .thinking } ?? .working
            default: status = .working
            }
        }
        let number = (lines.last?.number ?? -1) + 1
        lines.append(ActivityLine(number: number, runID: runID, text: text, status: status, running: kind == "working", tool: tool))
        if lines.count > Self.linesPerRun { lines.removeFirst(lines.count - Self.linesPerRun) }
        activity[runID] = lines
        if activity.count > Self.runsWithLines { pruneActivity() }
        return true
    }

    /// `run {chat_id, run_id, state, elapsed?}`: a run's new state (App.vue and companionState `transition`).
    mutating func runEvent(chat: ChatID?, data: JSONValue, time: Date?) -> WorldChange {
        guard let runID = data["run_id"]?.string, let stateText = data["state"]?.string else { return WorldChange() }
        let state = RunState(rawValue: stateText)
        let existing = runs[runID]
        var record = existing ?? RunRecord(row: RunDTO(id: runID, chatID: chat, state: state, created: time))
        let wasLive = existing?.row.state.isLive ?? false
        record.row.state = state
        if record.row.chatID == nil { record.row.chatID = chat }
        if let elapsed = data["elapsed"]?.double { record.row.elapsed = elapsed }
        if let time { record.row.updated = time }
        if state.isLive && !wasLive {
            // A fresh live stretch, new or resumed: its time is counted anew from `running`.
            record.tool = nil
            record.writing = false
            record.attempt = nil
            record.liveSince = nil
            record.label = nil
        }
        if state == .running, record.liveSince == nil, let time {
            record.liveSince = time.addingTimeInterval(-(record.row.elapsed ?? 0))
        }
        if state != .retryWait { record.attempt = nil }
        if !state.isLive {
            record.tool = nil
            record.writing = false
            record.liveSince = nil
        }
        record.settledByEvent = !state.isLive
        runs[runID] = record
        let chatID = record.row.chatID
        if state.isLive, let chatID {
            activeChat = chatID
            activeRun = runID
        } else if activeRun == runID {
            activeChat = nil
            activeRun = nil
        }
        // `waiting`: a run held for verification or with an uncertain step waits for the person (Reviews tab).
        var change = WorldChange(chats: true, runs: true, waiting: true)
        if !state.isLive { change.lists.insert(.screenSessions) }  // a window's access ends with its run
        if let chatID {
            bump(chatID, time)
            if !state.isLive { finishStreams(chat: chatID, run: runID) }
            if timelines[chatID] != nil { change.transcripts.insert(chatID) }
        }
        return change
    }

    /// `actions {chat_id, actions[]}`: the conversation's cards, all of them (App.vue replaces its list).
    mutating func actionsEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let chat, let list = data["actions"]?.array else { return WorldChange() }
        actions[chat] = list.compactMap { ActionDTO(json: $0, chatID: chat) }
        var change = WorldChange(chats: true, runs: true, waiting: true)
        if timelines[chat] != nil { change.transcripts.insert(chat) }
        return change
    }

    /// `question {chat_id, run_id, question_id, status, question?, message?}` (runEvents.ts applyRunEvent): the
    /// question leaves the list, comes back while pending, and the person's answer joins the conversation.
    mutating func questionEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let chat, let questionID = data["question_id"]?.string else { return WorldChange() }
        var list = questions[chat] ?? []
        list.removeAll { $0.id == questionID }
        if let question = data["question"].flatMap({ QuestionDTO(json: $0, chatID: chat) }), question.isPending {
            list.append(question)
        }
        questions[chat] = list
        var change = WorldChange(chats: true, runs: true, waiting: true)
        if timelines[chat] != nil {
            if let message = data["message"].flatMap(MessageDTO.init(json:)),
                timelines[chat]?.stored.contains(where: { $0.id == message.id }) == false
            {
                timelines[chat]?.stored.append(Self.item(message))
            }
            change.transcripts.insert(chat)
        }
        return change
    }

    /// `complete {chat_id, id, seconds}` and `stopped {chat_id, id}`: the reply with message id `id` ended. A reply
    /// that never streamed (a slash command's, answered at once) is read back from Pebble (App.vue showCommandReply).
    mutating func finishReply(chat: ChatID?, data: JSONValue, refetchIfUnseen: Bool) -> WorldChange {
        guard let chat, let id = data["id"]?.string else { return WorldChange() }
        var change = WorldChange()
        var seen = false
        var runID: RunID?
        if let index = timelines[chat]?.stored.firstIndex(where: { $0.id == id }) {
            timelines[chat]?.stored[index].isStreaming = false
            runID = timelines[chat]?.stored[index].runID
            seen = true
        }
        if let stream = streams[id] {
            runID = runID ?? stream.runID
            if timelines[chat] == nil {
                streams[id] = nil  // nobody shows it; opening the conversation reads Pebble's stored copy
            } else {
                streams[id]?.finished = true
            }
            seen = true
        }
        if let seconds = data["seconds"]?.double, let runID, runs[runID] != nil {
            runs[runID]?.replySeconds = seconds
        }
        if timelines[chat] != nil {
            change.transcripts.insert(chat)
            if !seen && refetchIfUnseen { change.needsChats.insert(chat) }
        }
        return change
    }

    /// `idle {chat_id, run_id}`: the worker is free. App.vue re-reads `state` and the conversation.
    mutating func idle(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let chat else { return WorldChange(needsState: true) }
        let runID = data["run_id"]?.string
        if runID == nil || activeRun == runID {
            activeChat = nil
            activeRun = nil
        }
        var change = WorldChange(chats: true, runs: true, waiting: true, needsState: true)
        if let runID, runs[runID]?.row.state.isLive == true {
            // The worker ended without a settle event (a setup failure): stop showing work, claim no outcome.
            runs[runID]?.row.state = .interrupted
            runs[runID]?.tool = nil
            runs[runID]?.writing = false
            runs[runID]?.liveSince = nil
        }
        finishStreams(chat: chat, run: nil)
        for (id, stream) in streams where stream.finished && timelines[stream.chatID] == nil { streams[id] = nil }
        if timelines[chat] != nil {
            change.transcripts.insert(chat)
            change.needsChats.insert(chat)
        }
        return change
    }

    /// `error {chat_id, run_id?, message}`: kept as the run's note until Pebble's own record arrives.
    mutating func errorEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let chat, let message = data["message"]?.string, !message.isEmpty else { return WorldChange() }
        guard let runID = data["run_id"]?.string ?? liveRunID(in: chat) ?? newestRun(in: chat)?.row.id,
            runs[runID] != nil
        else { return WorldChange() }
        runs[runID]?.row.error = message
        var change = WorldChange(runs: true, waiting: true)
        if timelines[chat] != nil { change.transcripts.insert(chat) }
        return change
    }

    /// `storage {changed, chat_id?}`: Recently deleted changed, or a conversation was deleted for good.
    mutating func storageEvent(_ data: JSONValue) -> WorldChange {
        switch data["changed"]?.string {
        case "deleted":
            var change = WorldChange(needsState: true, lists: [.trash])
            if let chat = data["chat_id"]?.string { change.formUnion(forget(chat: chat)) }
            return change
        case "recently_deleted":
            return WorldChange(needsState: true, lists: [.trash])
        default:
            return WorldChange(needsState: true)
        }
    }

    /// A conversation deleted for good: nothing of it stays on the phone.
    @discardableResult
    public mutating func forget(chat: ChatID) -> WorldChange {
        chats[chat] = nil
        actions[chat] = nil
        questions[chat] = nil
        timelines[chat] = nil
        processes[chat] = nil
        handoffOffers[chat] = nil
        pausedWindows[chat] = nil
        artifacts[chat] = nil
        for (id, record) in runs where record.row.chatID == chat {
            runs[id] = nil
            activity[id] = nil
            hostActivity[id] = nil
            plans[id] = nil
            checkedRuns.remove(id)
        }
        for (id, stream) in streams where stream.chatID == chat { streams[id] = nil }
        if activeChat == chat {
            activeChat = nil
            activeRun = nil
        }
        var change = WorldChange(chats: true, runs: true, waiting: true)
        change.transcripts.insert(chat)
        return change
    }

    /// Moved to Recently deleted (or back): it leaves the conversation list (or comes back to it).
    @discardableResult
    public mutating func markTrashed(chat: ChatID, _ trashed: Bool) -> WorldChange {
        var change = WorldChange(chats: true, runs: true, waiting: true, needsState: true, lists: [.trash])
        guard chats[chat] != nil else { return change }
        chats[chat]?.trashed = trashed
        change.transcripts.insert(chat)
        return change
    }

    mutating func markLiveRunsInterrupted() -> WorldChange {
        for (id, record) in runs where record.row.state.isLive {
            runs[id]?.row.state = .interrupted
            runs[id]?.tool = nil
            runs[id]?.writing = false
            runs[id]?.liveSince = nil
        }
        activeChat = nil
        activeRun = nil
        for (id, stream) in streams where !stream.finished { streams[id]?.finished = true }
        var change = WorldChange(overview: true, mac: true, chats: true, runs: true)
        change.transcripts = Set(timelines.keys)
        return change
    }

    // MARK: - Loading what Pebble sends back

    /// state(): Pebble, the conversation list and the newest runs.
    @discardableResult
    public mutating func load(_ state: StateDTO) -> WorldChange {
        version = state.version ?? version
        model = state.model ?? model
        settings = state.settings
        jobNotices = state.jobNotices
        memoryTypes = state.memoryTypes
        activeChat = state.active
        activeRun = state.activeRun
        // Pebble's list, plus the conversations open here that Pebble does not list yet (nothing stored in them).
        var nextChats: [ChatID: ChatDTO] = [:]
        for chat in state.chats where !chat.trashed { nextChats[chat.id] = chat }
        for (id, chat) in chats where nextChats[id] == nil && timelines[id] != nil && !chat.trashed {
            nextChats[id] = chat
        }
        chats = nextChats
        var nextRuns: [RunID: RunRecord] = [:]
        for row in state.runs { nextRuns[row.id] = Self.merged(runs[row.id], row) }
        // Older runs of the conversations open here stay (state lists only the newest 100).
        for (id, record) in runs where nextRuns[id] == nil {
            if let chat = record.row.chatID, timelines[chat] != nil { nextRuns[id] = record }
        }
        runs = nextRuns
        if let run = activeRun, runs[run]?.row.state.isLive == false {
            activeChat = nil  // the worker's run has already settled, as later events said
            activeRun = nil
        }
        for chat in Array(actions.keys) where chats[chat] == nil { actions[chat] = nil }
        for chat in Array(questions.keys) where chats[chat] == nil { questions[chat] = nil }
        for (id, stream) in streams where runs[stream.runID ?? ""]?.row.state.isLive != true {
            if timelines[stream.chatID] == nil { streams[id] = nil } else { streams[id]?.finished = true }
        }
        pruneActivity()
        return .everything(transcripts: Set(timelines.keys))
    }

    /// get_chat or remote.chat_tail: one conversation in full (or its newest messages), which also opens it here.
    @discardableResult
    public mutating func load(_ detail: ChatDetailDTO) -> WorldChange {
        let id = detail.chat.id
        var row = detail.chat
        if let known = chats[id]?.updated, (row.updated ?? .distantPast) < known { row.updated = known }
        chats[id] = row
        for run in detail.runs { runs[run.id] = Self.merged(runs[run.id], run) }
        actions[id] = detail.actions
        questions[id] = detail.questions.filter(\.isPending)
        artifacts[id] = detail.artifacts  // lane G
        var timeline = timelines[id] ?? Timeline()
        let fetched = detail.messages.map(Self.item)
        if let first = fetched.first, detail.hasOlder,
            let at = timeline.stored.firstIndex(where: { $0.id == first.id })
        {
            timeline.stored = Array(timeline.stored[..<at]) + fetched  // keep the older messages already shown
        } else {
            timeline.stored = fetched
            timeline.hasOlder = detail.hasOlder
        }
        // Pebble's stored copies replace what streamed in; a reply still streaming continues on top of its copy.
        for (messageID, stream) in streams where stream.chatID == id {
            guard let index = timeline.stored.firstIndex(where: { $0.id == messageID }) else { continue }
            let stored = timeline.stored[index].text
            if stored.hasPrefix(stream.text) {
                // Pebble's copy holds everything that streamed.
            } else if stream.text.hasPrefix(stored) {
                timeline.stored[index].text = stream.text
                timeline.stored[index].isStreaming = !stream.finished
            } else if !stream.finished {
                timeline.stored[index].text = stored + stream.text  // the stream began after the stored part
                timeline.stored[index].isStreaming = true
            }
            if timeline.stored[index].runID == nil { timeline.stored[index].runID = stream.runID }
            streams[messageID] = nil
        }
        let storedIDs = Set(timeline.stored.map(\.id))
        timeline.local.removeAll { storedIDs.contains($0.item.id) }
        timelines[id] = timeline
        var change = WorldChange(chats: true, runs: true, waiting: true)
        change.transcripts.insert(id)
        return change
    }

    /// remote.chat_before: older messages, put before the ones shown.
    @discardableResult
    public mutating func loadOlder(_ older: OlderMessagesDTO, chat: ChatID) -> WorldChange {
        guard var timeline = timelines[chat] else { return WorldChange() }
        let shown = Set(timeline.stored.map(\.id))
        timeline.stored = older.messages.filter { !shown.contains($0.id) }.map(Self.item) + timeline.stored
        timeline.hasOlder = older.hasOlder
        timelines[chat] = timeline
        var change = WorldChange()
        change.transcripts.insert(chat)
        return change
    }

    /// Stops following a conversation the phone no longer shows.
    public mutating func close(chat: ChatID) {
        timelines[chat] = nil
        for (id, stream) in streams where stream.chatID == chat && stream.finished { streams[id] = nil }
    }

    // MARK: - The person's own messages

    /// Shows a message the person sent from this phone at once, until Pebble's stored copy arrives.
    @discardableResult
    public mutating func addLocalMessage(chat: ChatID, id: MessageID, text: String, created: Date?) -> WorldChange {
        if timelines[chat] == nil { timelines[chat] = Timeline() }
        let item = MessageItem(id: id, role: .user, text: text, created: created)
        let order = nextSequence()
        timelines[chat]?.local.append(LocalMessage(item: item, sequence: order))
        var change = WorldChange()
        change.transcripts.insert(chat)
        return change
    }

    /// Pebble accepted it: the message takes Pebble's id, so its stored copy replaces it.
    @discardableResult
    public mutating func confirmLocalMessage(chat: ChatID, localID: MessageID, messageID: MessageID) -> WorldChange {
        guard let index = timelines[chat]?.local.firstIndex(where: { $0.item.id == localID }) else { return WorldChange() }
        if timelines[chat]?.stored.contains(where: { $0.id == messageID }) == true {
            timelines[chat]?.local.remove(at: index)
        } else {
            timelines[chat]?.local[index].item.id = messageID
        }
        var change = WorldChange()
        change.transcripts.insert(chat)
        return change
    }

    /// Pebble refused it: it leaves the conversation (the screen keeps the words in the composer).
    @discardableResult
    public mutating func removeLocalMessage(chat: ChatID, id: MessageID) -> WorldChange {
        timelines[chat]?.local.removeAll { $0.item.id == id }
        var change = WorldChange()
        change.transcripts.insert(chat)
        return change
    }

    /// A conversation the phone just made (new_chat), before Pebble lists it.
    @discardableResult
    public mutating func add(chat: ChatDTO) -> WorldChange {
        chats[chat.id] = chat
        if timelines[chat.id] == nil { timelines[chat.id] = Timeline() }
        var change = WorldChange(chats: true)
        change.transcripts.insert(chat.id)
        return change
    }

    /// A new title (chat_rename's answer).
    @discardableResult
    public mutating func rename(chat: ChatID, to title: String) -> WorldChange {
        guard chats[chat] != nil else { return WorldChange() }
        chats[chat]?.title = title
        var change = WorldChange(chats: true, runs: true, waiting: true)
        change.transcripts.insert(chat)
        return change
    }

    /// The bridge said who it is (welcome) or how the Mac is (remote.status).
    @discardableResult
    public mutating func setBridge(macName: String?, pebbleRunning: Bool?, pebbleVersion: String?) -> WorldChange {
        if let macName, !macName.isEmpty { self.macName = macName }
        if let pebbleRunning { self.pebbleRunning = pebbleRunning }
        if let pebbleVersion { version = pebbleVersion }
        return WorldChange(overview: true, mac: true)
    }

    @discardableResult
    public mutating func setMac(_ status: MacDTO) -> WorldChange {
        mac.merge(status)
        if let name = status.name, !name.isEmpty { macName = name }
        return WorldChange(mac: true)
    }

    /// The person saw the banner.
    public mutating func clearBanner() { banner = nil }

    // MARK: - Helpers

    /// The run that is live in a conversation: the one holding Pebble's worker, else the newest live one.
    func liveRunID(in chat: ChatID) -> RunID? {
        if activeChat == chat, let activeRun, runs[activeRun]?.row.state.isLive != false { return activeRun }
        return runs.values.filter { $0.row.chatID == chat && $0.row.state.isLive }.max(by: Self.olderFirst)?.row.id
    }

    func newestRun(in chat: ChatID) -> RunRecord? {
        runs.values.filter { $0.row.chatID == chat }.max(by: Self.olderFirst)
    }

    static func olderFirst(_ a: RunRecord, _ b: RunRecord) -> Bool {
        let left = a.row.created ?? .distantPast
        let right = b.row.created ?? .distantPast
        return left == right ? a.row.id < b.row.id : left < right
    }

    mutating func finishStreams(chat: ChatID, run: RunID?) {
        for (id, stream) in streams where stream.chatID == chat && (run == nil || stream.runID == nil || stream.runID == run) {
            streams[id]?.finished = true
        }
        if let indices = timelines[chat]?.stored.indices {
            for index in indices where timelines[chat]?.stored[index].isStreaming == true {
                if run == nil || timelines[chat]?.stored[index].runID == nil || timelines[chat]?.stored[index].runID == run {
                    timelines[chat]?.stored[index].isStreaming = false
                }
            }
        }
    }

    /// Moves a conversation up the list when something happened in it (Pebble's own `updated` follows on refetch).
    mutating func bump(_ chat: ChatID, _ time: Date?) {
        guard let time, chats[chat] != nil else { return }
        if (chats[chat]?.updated ?? .distantPast) < time { chats[chat]?.updated = time }
    }

    mutating func pruneActivity() {
        for id in Array(activity.keys) where runs[id] == nil { activity[id] = nil }
        for id in Array(hostActivity.keys) where runs[id] == nil { hostActivity[id] = nil }
        guard activity.count > Self.runsWithLines else { return }
        let keep = Set(
            activity.keys.compactMap { runs[$0] }.sorted(by: Self.olderFirst).suffix(Self.runsWithLines).map(\.row.id))
        for id in Array(activity.keys) where !keep.contains(id) { activity[id] = nil }
    }

    mutating func nextSequence() -> Int {
        sequence += 1
        return sequence
    }

    /// Keeps the live signals of a run Pebble re-reported, unless it went live or settled meanwhile.
    static func merged(_ existing: RunRecord?, _ row: RunDTO) -> RunRecord {
        var row = row
        guard var record = existing else {
            var fresh = RunRecord(row: row)
            if row.state == .running, let updated = row.updated {
                fresh.liveSince = updated.addingTimeInterval(-(row.elapsed ?? 0))
            }
            return fresh
        }
        if row.counts == nil { row.counts = record.row.counts }
        if row.created == nil { row.created = record.row.created }
        // A read answered before events that came later keeps the events' state: by Pebble's own clock (`updated`,
        // and the events' times), what the phone already knows is newer.
        if record.row.state != row.state, let mine = record.row.updated, let theirs = row.updated, mine > theirs {
            row.state = record.row.state
            row.error = record.row.error
            row.elapsed = record.row.elapsed ?? row.elapsed
            row.updated = mine
            record.row = row
            return record
        }
        if record.row.state != row.state { record.settledByEvent = false }
        if record.row.state.isLive != row.state.isLive || !row.state.isLive {
            record.tool = nil
            record.writing = false
            record.attempt = nil
            record.liveSince = nil
        }
        if row.state == .running, record.liveSince == nil, let updated = row.updated {
            record.liveSince = updated.addingTimeInterval(-(row.elapsed ?? 0))
        }
        record.row = row
        return record
    }

    static func item(_ message: MessageDTO) -> MessageItem {
        MessageItem(
            id: message.id, role: message.role, text: message.content, created: message.created, runID: message.runID,
            attachments: message.attachments)
    }

    /// Display text for an activity line: control and bidi characters removed, one line, at most `limit` characters
    /// (activity.ts clampText).
    static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        var result = ""
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let control = value < 0x20 || (0x7F...0x9F).contains(value) || value == 0x2028 || value == 0x2029
                || (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value)
            if control || scalar.properties.isWhitespace {
                if !lastWasSpace && !result.isEmpty { result.append(" ") }
                lastWasSpace = true
                continue
            }
            result.unicodeScalars.append(scalar)
            lastWasSpace = false
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
    }
}

/// What one change to the world touched, so the store republishes only that, and what it should read back.
public struct WorldChange: Sendable, Hashable {
    public var overview = false
    public var mac = false
    public var chats = false
    public var runs = false
    public var waiting = false
    public var banner = false
    /// Conversations open on the phone whose transcript changed.
    public var transcripts: Set<ChatID> = []
    /// Pebble's `state` should be read again (titles and order change without events).
    public var needsState = false
    /// Conversations to read again from Pebble.
    public var needsChats: Set<ChatID> = []
    /// Lists that changed on the Mac (read again if a screen has read them).
    public var lists: Set<ControlList> = []

    public init(
        overview: Bool = false, mac: Bool = false, chats: Bool = false, runs: Bool = false, waiting: Bool = false,
        banner: Bool = false, needsState: Bool = false, lists: Set<ControlList> = []
    ) {
        self.overview = overview
        self.mac = mac
        self.chats = chats
        self.runs = runs
        self.waiting = waiting
        self.banner = banner
        self.needsState = needsState
        self.lists = lists
    }

    public static func everything(transcripts: Set<ChatID>) -> WorldChange {
        var change = WorldChange(overview: true, mac: true, chats: true, runs: true, waiting: true)
        change.transcripts = transcripts
        return change
    }

    public mutating func formUnion(_ other: WorldChange) {
        overview = overview || other.overview
        mac = mac || other.mac
        chats = chats || other.chats
        runs = runs || other.runs
        waiting = waiting || other.waiting
        banner = banner || other.banner
        transcripts.formUnion(other.transcripts)
        needsState = needsState || other.needsState
        needsChats.formUnion(other.needsChats)
        lists.formUnion(other.lists)
    }

    public var isEmpty: Bool { self == WorldChange() }
}

extension MacDTO {
    /// Takes every field the newer report has.
    mutating func merge(_ newer: MacDTO) {
        name = newer.name ?? name
        batteryPercent = newer.batteryPercent ?? batteryPercent
        charging = newer.charging ?? charging
        onPower = newer.onPower ?? onPower
        keepAwake = newer.keepAwake ?? keepAwake
    }
}

extension PebbleWorld {
    /// `activity {chat_id, run_id, item}` (contract C4): one of Pebble's own timeline items, new or updated (same seq).
    mutating func hostActivityEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let run = data["run_id"]?.string, let item = data["item"].flatMap(RunActivityItem.init(json:)) else {
            return WorldChange()
        }
        hostActivity[run, default: [:]][item.seq] = item
        if let items = hostActivity[run], items.count > Self.linesPerRun, let oldest = items.keys.min() {
            hostActivity[run]?[oldest] = nil
        }
        var change = WorldChange()
        let owner = chat ?? runs[run]?.row.chatID
        if let owner, timelines[owner] != nil { change.transcripts.insert(owner) }
        return change
    }
}

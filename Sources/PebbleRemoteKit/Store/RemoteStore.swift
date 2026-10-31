import Foundation
import Observation
import PebbleProtocol

/// The one source of truth the screens read. It owns a RemoteClient, folds Pebble's events into the domain model,
/// and turns the person's taps into Pebble calls.
///
/// Interface owned by the lead (screens are built against it in parallel); bodies owned by lane A. Lane A may add
/// members freely; renaming or removing one needs a note in docs/TEAM_BOARD.md first.
///
/// How it works: one task consumes `client.updates` for the store's lifetime; every event goes through the pure
/// reducer (`PebbleWorld`), and the store republishes only what the event changed. Calls follow Pebble's own windows
/// (App.vue, RunPanel.vue in the Pebble checkout). Failures become `notice` in Pebble's own words (the bridge relays
/// Pebble's refusals unchanged) and are rethrown, so a screen can put the person's words back in the composer.
@MainActor
@Observable
public final class RemoteStore {
    // MARK: State the screens read

    public internal(set) var connection: ConnectionStatus = .idle
    /// nil until paired.
    public internal(set) var pairedMac: PairedMac?
    /// nil until the first `state` arrives.
    public internal(set) var pebble: PebbleOverview?
    /// A task runs on the Mac (Pebble's `active`). Pebble refuses model and effort changes until it ends, so the
    /// screens offer them only while this is false, as Pebble's own window does.
    public internal(set) var isPebbleWorking = false
    public internal(set) var mac: MacOverview?
    /// Newest activity first.
    public internal(set) var chats: [ChatSummary] = []
    /// Runs that are working or waiting for the person, newest first.
    public internal(set) var liveRuns: [LiveRun] = []
    /// Everything waiting for the person across chats, oldest first (the Reviews tab and its badge).
    public internal(set) var waiting: [WaitingItem] = []
    /// What the connected bridge supports; screens hide what is missing.
    public internal(set) var bridge: BridgeInfo?
    /// The latest refusal or failure to show once; the screen clears it after showing.
    public var notice: PersonFacingError?
    /// Pebble's banner for a conversation whose task ended or waits ("Pebble finished"); the screen clears it with
    /// `dismissBanner()` after showing it.
    public internal(set) var banner: ReplyBanner?
    /// Until when this phone may act on the Mac without another Face ID (contract C1); nil when locked or not known.
    /// Reads need no unlock. The client asks for Face ID itself when an action needs it; `unlock()` asks ahead.
    public internal(set) var unlockedUntil: Date?
    /// True when this store runs the in-app demo instead of a real Mac.
    public let isDemo: Bool

    // MARK: State the Control tab and Settings read (v0.2 P1; lists load with `loadControlLists()`)

    /// Projects Pebble already knows (the folders of its conversations), most recently used first.
    public internal(set) var projects: [ProjectRef] = []
    /// Every switch in Pebble's settings; nil until the first `state` arrives.
    public internal(set) var settings: PebbleSettings?
    /// Pebble's model profiles, and the one in use.
    public internal(set) var models: [ModelChoice] = []
    public internal(set) var currentModelID: String?
    /// Phones paired with the Mac.
    public internal(set) var devices: [MacDevice] = []
    /// Pebble's six memory layers, named in Pebble's words, with their switches.
    public internal(set) var memoryLayers: [MemoryLayer] = []
    /// Scheduled jobs across conversations, and the notices they left that wait for the person.
    public internal(set) var schedules: [ScheduleItem] = []
    public internal(set) var jobNotices: [JobNotice] = []
    /// Pebble's Toolbox: kept tools, tools Pebble asks about, and tools removed in the last ten minutes.
    public internal(set) var toolbox: [ToolboxEntry] = []
    public internal(set) var toolboxDecisions: [ToolboxDecision] = []
    public internal(set) var removedTools: [RemovedTool] = []
    /// Windows and tabs Pebble may use now, across recent conversations.
    public internal(set) var screenSessions: [ScreenSession] = []
    /// Conversations in Recently deleted, newest first.
    public internal(set) var trashed: [TrashedChat] = []
    /// Pebble's notification settings, whole (`notification_status`), for `setNotifications(_:)`.
    public internal(set) var notificationSettings: JSONValue?
    /// Photos and files waiting to go with each conversation's next message.
    public internal(set) var attachments: [ChatID: [AttachmentRef]] = [:]

    @ObservationIgnored let client: any RemoteClient
    /// Words written but not sent yet, by where they wait (UnsentText): kept across launches for the paired Mac.
    public let unsent: UnsentText
    @ObservationIgnored var transcripts: [ChatID: Transcript] = [:]
    /// New conversations not made on the Mac yet, by id, oldest first (RemoteStore+Projects).
    @ObservationIgnored var drafts: [(id: String, draft: ConversationDraft)] = []
    /// Folders this phone made on the Mac, by path, with when (RemoteStore+Projects): for ten minutes the bridge counts
    /// each one as known to this phone, so connecting it needs only the unlock (proposal v0.6).
    @ObservationIgnored var madeFolders: [String: Date] = [:]
    @ObservationIgnored let macStore: (any PairedMacStore)?
    /// Everything known about Pebble; the published properties above are derived from it.
    @ObservationIgnored var world = PebbleWorld()
    /// How many messages a conversation shows first (`remote.chat_tail`), and how many each "load older" adds.
    @ObservationIgnored public var pageSize = 50
    /// The phone's clock (when a screen session ends, which conversations are recent); tests replace it.
    @ObservationIgnored public var clock: @Sendable () -> Date = { Date() }
    /// Waits between steps of Stop everything; tests replace it.
    @ObservationIgnored var pause: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// Connecting and disconnecting, one after another (`start()`, `stop()`).
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    /// The call that ends the Mac's unlock while one is under way (`lock()`).
    @ObservationIgnored var locking: Task<Void, Never>?

    @ObservationIgnored private nonisolated(unsafe) var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var stateTask: Task<Void, Never>?
    @ObservationIgnored private var stateAgain = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var chatTasks: [ChatID: Task<Void, Never>] = [:]
    @ObservationIgnored private var chatAgain: Set<ChatID> = []
    /// Lists a screen has read; an event that changes one reads it again.
    @ObservationIgnored var loadedLists: Set<ControlList> = []
    @ObservationIgnored private var listTasks: [ControlList: Task<Void, Never>] = [:]
    @ObservationIgnored private var listAgain: Set<ControlList> = []
    /// Conversations whose commands a screen shows: their `process_list` is read again on Pebble's events
    /// (RemoteStore+Recovery, as ExecutionOutput.vue does).
    @ObservationIgnored var processChats: Set<ChatID> = []
    @ObservationIgnored var processTasks: [ChatID: Task<Void, Never>] = [:]
    @ObservationIgnored var processAgain: Set<ChatID> = []

    /// - Parameter unsent: where unsent words are kept; the default keeps them in memory (the demo, tests).
    public init(
        client: any RemoteClient, pairedMac: PairedMac? = nil, isDemo: Bool = false, macStore: (any PairedMacStore)? = nil,
        unsent: UnsentText = UnsentText()
    ) {
        self.client = client
        self.unsent = unsent
        self.macStore = macStore
        self.pairedMac = pairedMac ?? (try? macStore?.load()) ?? nil
        self.isDemo = isDemo
        let updates = client.updates
        updatesTask = Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                self.handle(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: Lifecycle

    /// Connects if paired. Called when the scene becomes active.
    public func start() {
        guard let mac = pairedMac else { return }
        let client = self.client
        enqueue { await client.connect(to: mac) }
    }

    /// Ends this phone's unlock on the Mac (S-05, `lock()`), then closes the connection politely. Called when the
    /// scene goes to the background. Unsent words are written to their file first.
    public func stop() {
        unsent.saveNow()
        let client = self.client
        // Holds the store until the unlock has ended: a store that is replaced right after (the demo starts) still asks.
        enqueue { [self] in
            await lock()
            await client.disconnect()
        }
    }

    /// Runs connecting and disconnecting in the order they were asked: a stop that is still ending the Mac's unlock
    /// must not close the connection a quick return to the foreground has just asked for.
    private func enqueue(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let previous = lifecycle
        lifecycle = Task {
            await previous?.value
            await work()
        }
    }

    /// Pairs with the Mac that showed the link, keeps it, and connects. Pairing another Mac replaces the old one (its
    /// keys are deleted); pairing the same Mac again keeps what the phone knows. Once the phone has sent its
    /// signatures, `showingCode` gets the six digits the Mac shows too (X-1): the person checks that they match and
    /// confirms on the Mac, which takes up to two minutes. Cancelling the calling task is the person leaving.
    public func pair(
        using link: PairingLink, deviceName: String, showingCode: @escaping @Sendable (PairingCode) -> Void = { _ in }
    ) async throws {
        let previous = pairedMac
        let mac: PairedMac
        do {
            mac = try await client.pair(link, deviceName: deviceName, showingCode: showingCode)
        } catch {
            throw report(error)
        }
        do {
            try macStore?.save(mac)
        } catch {
            notice = PersonFacingError(message: StoreWords.keyNotKept)
            throw error
        }
        if let previous, previous.bridgeID != mac.bridgeID {
            await client.forget(previous)
            forgetWhatWasShown()
        }
        pairedMac = mac
        await client.connect(to: mac)  // the pairing connection closed; this opens the working one
    }

    /// Forgets the Mac on this phone and, if reachable, removes this phone from the Mac's paired devices. Removing it
    /// there needs the unlock, so a locked phone asks for Face ID first; otherwise the Mac kept a stale row. Cancelled or
    /// unreachable, the phone forgets the Mac anyway (the confirmation says where to remove it on the Mac).
    public func forgetMac() async {
        if let mac = pairedMac {
            if offers("remote.revoke_device") {
                if !isUnlocked { try? await unlock() }
                // Not through `act`: a refusal here must not leave a notice over the pairing screen that follows.
                let params: JSONValue = ["device_id": .string(mac.deviceID)]
                do {
                    _ = try await client.call("remote.revoke_device", params)
                } catch RemoteCallError.refused(let refusal) where refusal.code == BridgeErrorCode.proofRequired.rawValue {
                    _ = try? await client.callElevated("remote.revoke_device", params, reason: StoreWords.unlockReason)
                } catch {}
            }
            await client.forget(mac)
        }
        try? macStore?.remove()
        await client.disconnect()
        pairedMac = nil
        forgetWhatWasShown()
    }

    private func forgetWhatWasShown() {
        bridge = nil
        connection = .idle
        banner = nil
        unlockedUntil = nil
        world = PebbleWorld()
        transcripts = [:]
        drafts = []
        unsent.removeAll()  // words written to the Mac that is gone
        loadedLists = []
        (models, devices, schedules, toolbox, toolboxDecisions, removedTools) = ([], [], [], [], [], [])
        (screenSessions, trashed, notificationSettings, attachments) = ([], [], nil, [:])
        publish(.everything(transcripts: []))
    }

    /// Reads Pebble's state again, then every conversation open here and every one with something waiting.
    public func refresh() async {
        if refreshTask != nil {
            refreshAgain = true
        } else {
            refreshTask = Task { [weak self] in
                guard let self else { return }
                repeat {
                    self.refreshAgain = false
                    await self.refreshEverything()
                } while self.refreshAgain
                self.refreshTask = nil
            }
        }
        await refreshTask?.value
    }

    // MARK: Conversations

    /// The live model of one conversation; it loads on first use and stays current while connected.
    public func transcript(for id: ChatID) -> Transcript {
        if let existing = transcripts[id] { return existing }
        let made = Transcript(chatID: id, store: self)
        transcripts[id] = made
        made.update(from: world)
        made.isLoading = true
        requestChat(id)
        return made
    }

    /// Conversations whose title holds the words (matched here, as Pebble's window does), then those whose messages
    /// do (Pebble's `chat_search`, for two or more characters).
    public func search(_ query: String) async throws -> [ChatSummary] {
        let words = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty else { return chats }
        var found = chats.filter { $0.title.localizedStandardContains(words) }
        guard words.count >= 2, offers("chat_search") else { return found }
        let result: JSONValue
        do {
            result = try await client.call("chat_search", ["query": .string(words)])
        } catch {
            throw report(error)
        }
        let byID = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let shown = Set(found.map(\.id))
        for match in result["matches"]?.array ?? [] {
            if let id = match["id"]?.string, !shown.contains(id), let summary = byID[id] { found.append(summary) }
        }
        return found
    }

    /// Starts a new conversation (in Pebble's default project) and sends the first message, if any.
    public func newChat(firstMessage: String?) async throws -> ChatID {
        try await newChat(firstMessage: firstMessage, in: nil)
    }

    /// Sends a message. While a run is live in the chat, it reaches the run as guidance: Pebble's own windows send it
    /// with `send` (App.vue `send()`: a follow-up while the conversation holds the active run), and Pebble's `send`
    /// steers the live run and keeps the message in the conversation, which `run_steer` would not.
    public func send(_ text: String, in chat: ChatID) async throws {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let localID = "local-" + UUID().uuidString
        // Attachments go with a new task only, never with guidance or a slash command (App.vue's rule; Pebble refuses
        // them there), and stay for the next task otherwise.
        let sources = words.hasPrefix("/") || world.isLive(chat: chat) ? [] : (attachments[chat] ?? [])
        var params: [String: JSONValue] = ["id": .string(chat), "text": .string(words)]
        if !sources.isEmpty { params["source_ids"] = .array(sources.map { .string($0.id) }) }
        publish(world.addLocalMessage(chat: chat, id: localID, text: words, created: clock()))
        do {
            let result = try await client.call("send", .object(params))
            let sent = SendResultDTO(json: result)
            if !sources.isEmpty { attachments[chat] = nil }  // Pebble took them with the message
            if let messageID = sent.messageID {
                publish(world.confirmLocalMessage(chat: chat, localID: localID, messageID: messageID))
            }
            if sent.command { requestChat(chat) }  // a slash command's reply is stored at once, without tokens
            requestState()  // a first message names the conversation; no event says so
        } catch {
            publish(world.removeLocalMessage(chat: chat, id: localID))
            throw report(error)
        }
    }

    /// Whether a message sent now reaches a working run as guidance ("Tell Pebble while it works").
    public func sendsGuidance(in chat: ChatID) -> Bool { world.isLive(chat: chat) }

    public func stop(chat: ChatID) async throws {
        try await perform("cancel", ["id": .string(chat)])  // App.vue stop(): the live run, else a waiting one
    }

    public func pause(chat: ChatID) async throws {
        var params: [String: JSONValue] = ["id": .string(chat)]
        if let run = world.liveRun(for: chat) { params["run_id"] = .string(run.id) }
        try await perform("run_pause", .object(params))
    }

    public func resume(chat: ChatID) async throws {
        var params: [String: JSONValue] = ["id": .string(chat)]
        let resumable: Set<RunState> = [.paused, .stopped, .interrupted, .failed, .budgetExhausted]
        if let run = world.newestRun(in: chat), resumable.contains(run.row.state) { params["run_id"] = .string(run.row.id) }
        try await perform("run_resume", .object(params))
    }

    public func rename(chat: ChatID, to title: String) async throws {
        let result: JSONValue
        do {
            result = try await client.call("chat_rename", ["id": .string(chat), "title": .string(title)])
        } catch {
            throw report(error)
        }
        publish(world.rename(chat: chat, to: result["title"]?.string ?? title))
    }

    // MARK: Reviews

    /// Approves a card. Asks for Face ID (an elevated call).
    public func approve(_ item: ReviewItem) async throws {
        let useFull = bridge.map { $0.methods.contains("approve") || !$0.methods.contains("approve_simple") } ?? true
        let method = useFull ? "approve" : "approve_simple"
        let params: JSONValue = ["id": .string(item.chatID), "action_id": .string(item.actionID)]
        do {
            _ = try await client.callElevated(method, params, reason: StoreWords.approveReason(item.title))
        } catch {
            throw report(error)
        }
        requestChat(item.chatID)  // App.vue decide() reads the conversation back
    }

    public func reject(_ item: ReviewItem) async throws {
        let useFull = bridge.map { $0.methods.contains("reject") || !$0.methods.contains("reject_simple") } ?? true
        let method = useFull ? "reject" : "reject_simple"
        try await perform(method, ["id": .string(item.chatID), "action_id": .string(item.actionID)])
        requestChat(item.chatID)
    }

    /// Pebble wants each prompt answered exactly once: a chosen option (`{option_id}`) or written words (`{text}`),
    /// never both (interaction.canonical_answer), so an option's extra text is not sent.
    public func answer(_ card: QuestionCard, with answers: [String: QuestionAnswer]) async throws {
        var object: [String: JSONValue] = [:]
        for (promptID, answer) in answers {
            switch answer {
            case .option(let optionID, _): object[promptID] = ["option_id": .string(optionID)]
            case .text(let words): object[promptID] = ["text": .string(words)]
            }
        }
        try await perform(
            "question_answer",
            [
                "id": .string(card.chatID), "question_id": .string(card.questionID), "revision": .int(card.revision),
                "answers": .object(object),
            ])
    }

    /// Skips an optional question, or cancels a required one (which stops its run, as on the Mac).
    public func dismiss(_ card: QuestionCard) async throws {
        try await perform(
            "question_cancel",
            ["id": .string(card.chatID), "question_id": .string(card.questionID), "revision": .int(card.revision)])
    }

    // MARK: Control

    /// Changes Pebble's permission mode. Asks for Face ID; Pebble refuses while a task runs.
    public func setPermissionMode(_ mode: PermissionMode) async throws {
        guard let permissions = world.settings?.permissions(withMode: mode) else {
            let failure = PersonFacingError(message: StoreWords.settingsNotRead, code: StoreWords.Code.notConnected)
            notice = failure
            throw RemoteCallError.refused(failure)
        }
        try await setSetting("permissions", to: permissions)
    }

    public func setFastReplies(_ value: FastReplies) async throws {
        try await setSetting("fast_replies", to: .string(value.rawValue))
    }

    public func setStealth(_ on: Bool) async throws {
        try await setSetting("stealth", to: .bool(on))
    }

    /// Keeps the Mac awake (R3). Neither Pebble's bridge nor the mock wants Face ID for it, on battery either (the bridge
    /// alignment review, 2026-10-31), so it goes with the unlock, and elevated once if a bridge answers `proof_required`.
    public func setKeepAwake(_ on: Bool) async throws {
        let params: JSONValue = ["on": .bool(on)]
        var result: JSONValue
        do {
            do {
                result = try await client.call("remote.keep_awake", params)
            } catch RemoteCallError.refused(let refusal) where refusal.code == BridgeErrorCode.proofRequired.rawValue {
                result = try await client.callElevated("remote.keep_awake", params, reason: StoreWords.keepAwakeReason)
            }
        } catch {
            throw report(error)
        }
        var mac = MacDTO(json: .object([:]))
        mac.keepAwake = result["keep_awake"]?.bool ?? on
        publish(world.setMac(mac))
    }

    /// Stops every live run: the one working first, then those waiting for the person (Pebble refuses to stop a
    /// waiting run in another conversation while one works, so this waits for the worker to come free).
    public func stopEverything() async throws {
        let targets = world.runsToStop()
        var firstFailure: Error?
        var stoppedLive = false
        for target in targets {
            if !target.live && stoppedLive {
                for _ in 0..<50 where world.activeRun != nil { await pause(.milliseconds(200)) }
            }
            do {
                _ = try await client.call("cancel", ["id": .string(target.chat), "run_id": .string(target.run)])
                if target.live { stoppedLive = true }
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure { throw report(firstFailure) }
    }

    /// The person saw Pebble's banner.
    public func dismissBanner() {
        banner = nil
        world.clearBanner()
    }

    // MARK: - Updates from the client

    func handle(_ update: ClientUpdate) {
        switch update {
        case .status(let status):
            if connection != status { connection = status }
        case .welcome(let info):
            bridge = info
            publish(world.setBridge(macName: info.macName, pebbleRunning: info.pebbleRunning, pebbleVersion: info.pebbleVersion))
            if !info.resumed || pebble == nil {
                requestRefresh()
            } else {
                requestMacStatus()
            }
        case .event(let event):
            publish(world.apply(event))
            commandsMayHaveChanged(event)
        case .resyncNeeded:
            requestRefresh()
        case .unlocked(let until):
            if unlockedUntil != until { unlockedUntil = until }
        }
    }

    /// Republishes what a change touched, and starts the reads it asks for.
    func publish(_ change: WorldChange) {
        let working = world.activeChat != nil
        if isPebbleWorking != working { isPebbleWorking = working }
        if change.overview {
            let value = world.overview()
            if pebble != value { pebble = value }
            let all = world.pebbleSettings()
            if settings != all { settings = all }
            let model = world.currentModel().profileID
            if currentModelID != model { currentModelID = model }
            if jobNotices != world.jobNotices { jobNotices = world.jobNotices }
            let layers = world.memoryLayers()
            if memoryLayers != layers { memoryLayers = layers }
        }
        if change.mac {
            let value = world.macOverview()
            if mac != value { mac = value }
        }
        if change.chats {
            let value = world.chatSummaries()
            if chats != value { chats = value }
            let folders = world.projects()
            if projects != folders { projects = folders }
        }
        if change.runs {
            let value = world.liveRuns()
            if liveRuns != value { liveRuns = value }
        }
        if change.waiting {
            let value = world.waitingItems()
            if waiting != value { waiting = value }
        }
        if change.banner, banner != world.banner { banner = world.banner }
        for (id, transcript) in transcripts {
            if change.transcripts.contains(id) {
                transcript.update(from: world)
            } else if change.chats || change.runs {
                transcript.updateHeader(from: world)
            }
        }
        if change.needsState { requestState() }
        for chat in change.needsChats where transcripts[chat] != nil { requestChat(chat) }
        for list in change.lists where loadedLists.contains(list) { requestList(list) }
    }

    /// Reads one of the Control tab's lists again, coalescing requests that arrive while a read is under way.
    func requestList(_ list: ControlList) {
        if listTasks[list] != nil {
            listAgain.insert(list)
            return
        }
        listTasks[list] = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.listAgain.remove(list)
                await self.load(list)
            } while self.listAgain.contains(list)
            self.listTasks[list] = nil
        }
    }

    // MARK: - Reading from Pebble

    func requestRefresh() {
        Task { await self.refresh() }
    }

    /// Reads `state` again, coalescing requests that arrive while a read is under way.
    func requestState() {
        if stateTask != nil {
            stateAgain = true
            return
        }
        stateTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.stateAgain = false
                _ = await self.readState(reportFailure: false)
            } while self.stateAgain
            self.stateTask = nil
        }
    }

    /// Reads `state` again and waits for it, so a setter returns once the store shows Pebble's new value: a switch
    /// that shows only confirmed values moves as its spinner ends (design review A2).
    func refreshState() async {
        requestState()
        await stateTask?.value
    }

    /// Reads a conversation and `state` again and waits for the conversation, so a call returns once the store shows
    /// Pebble's answer (a run's new state, a new card).
    func refreshChat(_ chat: ChatID) async {
        requestState()
        requestChat(chat)
        await chatTasks[chat]?.value
    }

    /// Reads one conversation again, coalescing requests that arrive while a read is under way.
    func requestChat(_ chat: ChatID) {
        if chatTasks[chat] != nil {
            chatAgain.insert(chat)
            return
        }
        chatTasks[chat] = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.chatAgain.remove(chat)
                await self.readChat(chat)
            } while self.chatAgain.contains(chat)
            self.chatTasks[chat] = nil
        }
    }

    func requestMacStatus() {
        guard offers("remote.status") else { return }
        Task { await self.readMacStatus() }
    }

    func refreshEverything() async {
        guard await readState(reportFailure: true) else { return }
        await readMacStatus()
        var chatsToRead = Set(transcripts.keys)
        chatsToRead.formUnion(world.chatsWithSomethingWaiting())
        for chat in chatsToRead.sorted() {
            await readChat(chat)
        }
    }

    @discardableResult
    func readState(reportFailure: Bool) async -> Bool {
        do {
            let result = try await client.call("state", [:])
            guard let state = StateDTO(json: result) else {
                if reportFailure { notice = unreadable().personFacing }
                return false
            }
            publish(world.load(state))
            return true
        } catch {
            if reportFailure { _ = report(error) }
            return false
        }
    }

    func readMacStatus() async {
        guard offers("remote.status"), let result = try? await client.call("remote.status", [:]) else { return }
        let status = RemoteStatusDTO(json: result)
        publish(world.setBridge(macName: status.mac?.name, pebbleRunning: status.pebbleRunning, pebbleVersion: status.pebbleVersion))
        if let mac = status.mac { publish(world.setMac(mac)) }
        learnEndpoints(status.endpoints)
    }

    /// Keeps the addresses the paired Mac reports for itself (`remote.status`) with the pairing, so the next connection
    /// tries them too: a Tailscale address that came after pairing then reaches the Mac from anywhere (R1). They arrive
    /// over the pinned connection to the paired bridge and are checked as a pairing link's are (S-06, S-07). The Mac's
    /// current addresses come first; the ones paired with stay after them, up to the link's limit.
    func learnEndpoints(_ reported: [Endpoint]) {
        guard !isDemo, var mac = pairedMac else { return }
        var merged: [Endpoint] = []
        for endpoint in reported + mac.endpoints where Endpoint.isValidHost(endpoint.host) && !merged.contains(endpoint) {
            merged.append(endpoint)
        }
        merged = Array(merged.prefix(PairingLink.maximumEndpoints))
        guard !reported.isEmpty, merged != mac.endpoints else { return }
        mac.endpoints = merged
        do {
            try macStore?.save(mac)
        } catch {
            return  // the pairing keeps its addresses; the next status read tries again
        }
        pairedMac = mac
    }

    /// `remote.chat_tail` when the bridge offers it (the newest messages), else `get_chat` (all of them).
    func readChat(_ chat: ChatID) async {
        let tail = offers("remote.chat_tail")
        defer { transcripts[chat]?.isLoading = false }
        do {
            let result =
                tail
                ? try await client.call("remote.chat_tail", ["id": .string(chat), "limit": .int(pageSize)])
                : try await client.call("get_chat", ["id": .string(chat)])
            guard let detail = ChatDetailDTO(json: result) else { return }
            publish(world.load(detail))
        } catch {
            // Read quietly: a conversation shows what the phone already knows, and the next refresh tries again.
        }
    }

    func loadOlder(in chat: ChatID) async {
        guard world.hasOlder(in: chat), offers("remote.chat_before"), let first = world.firstStoredMessageID(in: chat)
        else { return }
        do {
            let result = try await client.call(
                "remote.chat_before", ["id": .string(chat), "before": .string(first), "limit": .int(pageSize)])
            guard let older = OlderMessagesDTO(json: result) else { return }
            publish(world.loadOlder(older, chat: chat))
        } catch {
            _ = report(error)
        }
    }

    // MARK: - Helpers

    /// The bridge offers this method. Before the first welcome nothing is known, so everything is tried.
    func offers(_ method: String) -> Bool {
        bridge?.methods.contains(method) ?? false
    }

    /// One call whose answer the store does not need: Pebble's events bring the change.
    func perform(_ method: String, _ params: JSONValue) async throws {
        do {
            _ = try await client.call(method, params)
        } catch {
            throw report(error)
        }
    }

    /// Shows a failure once, in Pebble's words when Pebble or the bridge wrote them, and returns it to rethrow. The
    /// person cancelling Face ID is not a failure.
    func report(_ error: Error) -> Error {
        if let failure = Self.personFacing(error) { notice = failure }
        return error
    }

    static func personFacing(_ error: Error) -> PersonFacingError? {
        switch error as? RemoteCallError {
        case .refused(let refusal)?: refusal
        case .cancelledByPerson?: nil
        case .notConnected?: PersonFacingError(message: StoreWords.notConnected, code: StoreWords.Code.notConnected)
        case .timedOut?: PersonFacingError(message: StoreWords.timedOut, code: StoreWords.Code.timedOut)
        case .transport?: PersonFacingError(message: StoreWords.connectionDropped, code: StoreWords.Code.transport)
        case .notImplemented?: PersonFacingError(message: StoreWords.notOffered, code: StoreWords.Code.notOffered)
        case nil:
            (error as? PersonFacingError) ?? PersonFacingError(message: StoreWords.connectionDropped, code: StoreWords.Code.transport)
        }
    }

    func unreadable() -> RemoteCallError {
        .refused(PersonFacingError(message: StoreWords.unreadableAnswer, code: StoreWords.Code.unreadable))
    }
}

extension RemoteCallError {
    var personFacing: PersonFacingError? {
        if case .refused(let refusal) = self { refusal } else { nil }
    }
}

/// One conversation, kept current while the app is connected.
@MainActor
@Observable
public final class Transcript: Identifiable {
    public nonisolated let chatID: ChatID
    public nonisolated var id: ChatID { chatID }
    public internal(set) var title: String = ""
    /// The project's folder name; nil in Companion.
    public internal(set) var project: String?
    /// The project's folder on the Mac (Pebble's `workspace`); nil in Companion.
    public internal(set) var workspace: String?
    public internal(set) var items: [TranscriptItem] = []
    /// The run working in this chat now, if any.
    public internal(set) var run: LiveRun?
    public internal(set) var isLoading = false
    public internal(set) var hasOlder = false
    /// Pebble's counts for the finished runs, by run id, for their end lines.
    public internal(set) var recaps: [RunID: RunRecap] = [:]
    /// A message sent now reaches the working run as guidance ("Tell Pebble while it works").
    public internal(set) var sendsGuidance = false
    /// The conversation's current task when it is paused, stopped, interrupted, failed, out of budget, held for
    /// verification or has an uncertain step; its menu offers Resume for the ones that can resume.
    public internal(set) var task: TaskAttention?
    /// Lane G: the conversation's views (forms, tables, charts …), oldest first.
    public internal(set) var views: [PebbleArtifact] = []
    /// Lane G: how activity lines draw as the work view's cards, by the line's id (`TranscriptItem.activity`'s `id`).
    public internal(set) var workLines: [String: WorkLine] = [:]
    /// Lane G: each run's plan, for the work view's header while the run works.
    public internal(set) var plans: [RunID: WorkPlan] = [:]

    @ObservationIgnored weak var store: RemoteStore?

    init(chatID: ChatID, store: RemoteStore?) {
        self.chatID = chatID
        self.store = store
    }

    public func loadOlder() async {
        await store?.loadOlder(in: chatID)
    }

    /// The conversation holds a message. Pebble's window reuses a conversation without one when the person picks a
    /// project (App.vue `openProject`, `chooseProject`); one with messages stays where it is, and the project starts a
    /// new conversation.
    public var hasMessages: Bool {
        items.contains { if case .message = $0 { true } else { false } }
    }

    func update(from world: PebbleWorld) {
        let next = world.transcriptItems(for: chatID)
        if items != next { items = next }
        let older = world.hasOlder(in: chatID)
        if hasOlder != older { hasOlder = older }
        updateHeader(from: world)
        updateViews(from: world)  // lane G
    }

    /// Lane G: the conversation's views and the work view's cards.
    func updateViews(from world: PebbleWorld) {
        let shown = world.views(in: chatID)
        if views != shown { views = shown }
        let lines = world.workLines(for: chatID)
        if workLines != lines { workLines = lines }
        let steps = world.plans(for: chatID)
        if plans != steps { plans = steps }
    }

    func updateHeader(from world: PebbleWorld) {
        let name = world.title(of: chatID)
        if title != name { title = name }
        let folder = world.project(of: chatID)
        if project != folder { project = folder }
        let path = world.workspace(of: chatID)
        if workspace != path { workspace = path }
        let live = world.liveRun(for: chatID)
        if run != live { run = live }
        let guidance = world.isLive(chat: chatID)
        if sendsGuidance != guidance { sendsGuidance = guidance }
        let counts = world.runRecaps(for: chatID)
        if recaps != counts { recaps = counts }
        let current = world.taskAttention(for: chatID)
        if task != current { task = current }
    }
}

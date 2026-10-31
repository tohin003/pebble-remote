import Foundation
import PebbleProtocol

/// A believable simulated Pebble for "Try the demo" and previews. It speaks the same calls and sends the same events,
/// with the same payload shapes, as Pebble behind a real bridge, so the demo runs through the real store and reducer.
///
/// On connect a run is already working in "Fix the login redirect loop" and its reply streams in token by token, with
/// progress from Pebble's real tools (Read, Grep, Edit, RunTests). "Update the README for 2.0" waits for approval of
/// `npm test`; "Plan the onboarding emails" waits for an answer; one run finished and one failed. Sending, Stop, Pause,
/// Resume, approving, rejecting, answering and the settings react as Pebble does, refusals in Pebble's own words.
///
/// `pace` scales every pause (1 is lifelike, 0 runs scripts with no waiting, for tests); `now` is the demo's clock.
/// Events sent while disconnected are kept and replayed on the next connect (as the bridge's resume does).
public actor DemoClient: RemoteClient {
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    public nonisolated let updates: AsyncStream<ClientUpdate>
    private let continuation: AsyncStream<ClientUpdate>.Continuation
    private let pace: Double
    let now: @Sendable () -> Date
    private let sleeper: Sleeper
    private let autoplay: Bool

    var chats: [DemoChat]
    var runs: [String: DemoRun]
    /// Text each live run has written so far.
    private var answers: [String: String] = [:]
    var settings: [String: JSONValue]
    private var macStatus: [String: JSONValue]
    var activeChat: String?
    var activeRun: String?
    private var scripts: [String: Task<Void, Never>] = [:]
    private var connected = false
    private var everConnected = false
    private var missed: [PebbleEvent] = []
    private var seq = 0
    private var counter = 0
    /// Schedules, the Toolbox, screen sessions, notification settings, models and settings.
    var workflows: DemoWorkflows
    /// Conversations in Recently deleted, with when.
    var trashedAt: [String: Date] = [:]
    /// Photos and files waiting for each conversation's next task, and pastes still arriving.
    private var sources: [String: [JSONValue]] = [:]
    private var uploads: [String: (chat: String, name: String, data: Data)] = [:]
    /// What each run did, as run_activity items.
    private var activityItems: [String: [JSONValue]] = [:]
    /// Until when this phone may act (contract C1); the demo starts locked.
    private var unlockedUntil: Date?
    /// Held tasks, uncertain outcomes, commands and model handoffs (DemoClient+Recovery).
    var recovery = DemoRecovery()
    /// The demo Mac's folders, and the ones made while trying the demo (DemoFolders).
    var folders = DemoFolders()
    /// What the demo's Pebble remembers, for Settings › Memory and "/memory" (lane Z, DemoMemory).
    var memory: DemoMemory
    /// Pebble's views in each conversation (lane G: DemoViews).
    var views: DemoViews
    /// Attempts at the demo's quizzes, and their answer keys (lane Q: DemoQuizzes).
    var quizzes = DemoQuizzes()
    /// Goals, agents, task windows, rewinds and browsers for the Details screen (DemoDetails).
    var details: DemoDetails
    /// Lane S: the Settings controls that were "On your Mac" rows (DemoSettings, DemoClient+Settings).
    var settingsDemo = DemoSettings()
    /// Lane T: exports and views' earlier revisions (DemoExports, DemoClient+Exports).
    var exportsDemo: DemoExports

    /// Every event the demo has sent, oldest first (the last 2,000).
    public private(set) var sent: [PebbleEvent] = []

    /// Methods the demo answers, as a bridge's welcome lists them.
    public static let methods: Set<String> = [
        "state", "get_chat", "chat_search", "new_chat", "send", "cancel", "run_pause", "run_resume", "approve", "reject",
        "approve_simple", "reject_simple", "question_answer", "question_cancel", "setting", "chat_rename",
        "remote.status", "remote.devices", "remote.revoke_device", "remote.keep_awake", "remote.chat_tail",
        "remote.chat_before", "remote.ping", "remote.screenshot", "run_list", "run_activity", "model_profiles",
        "model_select", "model_effort", "notification_status", "notification_ack", "job_list", "job_get",
        "job_preview", "job_create", "job_pause", "job_preview_resume", "job_resume", "job_delete", "toolbox_list",
        "toolbox_get", "toolbox_remove", "toolbox_undo_remove", "toolbox_decide", "screen_sessions",
        "screen_session_revoke", "screen_handoff_done", "storage_summary", "storage_trash_chat",
        "storage_restore_chat", "storage_purge_chat", "attach_bytes", "remove_source",
        // Proposal v0.5: where conversations start, and the composer's "+" menu.
        "set_workspace", "attach_url", "terminal_propose", "remote.folders",
        // Proposal v0.6: a new folder, made from the phone.
        "remote.folder_create",
        // Finishing and recovering a task (lane R).
        "undo", "run_held_tests", "run_held_finish", "run_held_accept", "run_readback", "run_reconcile",
        "process_list", "process_terminal", "process_read", "process_stop", "process_input_human", "process_inspect",
        "process_dismiss", "model_handoff_preview", "model_handoff_approve", "model_handoff_start",
        // The composer's "/" commands and Settings › Memory (lane Z).
        "command_catalogue", "memory_list", "memory_delete", "memory_contests", "memory_resolve_contest",
        // The conversation's Details (lane Y): goals, agents, context, rewind, Chrome, Pebble's browser, tab grants.
        "goal_list", "goal_get", "goal_create", "goal_state", "goal_continue", "goal_criterion_check",
        "goal_criterion_review", "goal_criterion_add", "agent_list", "agent_steer", "agent_cancel", "context_inspect",
        "context_compact", "rewind_preview", "rewind_apply", "browser_extension_status", "browser_extension_pause",
        "browser_extension_resume", "browser_extension_stop", "browser_status", "browser_start", "browser_stop",
        "browser_tabs", "screen_session_grant",
        // Pebble's views (lane G, contract 3.12).
        "artifact_get", "artifact_submit", "artifact_refresh",
        // A reply's source markers ([S1]).
        "research_sources",
        // Taking a quiz (lane Q).
        "quiz_attempt", "quiz_start", "quiz_save", "quiz_submit", "quiz_share",
        // Settings controls that were "On your Mac" rows (lane S).
        "memory_candidates", "memory_resolve", "memory_maintain", "memory_save", "memory_clear", "extensions",
        "skill_inspect", "extension_toggle", "storage_refresh", "storage_trash_all", "storage_purge_all",
        "telemetry_get", "telemetry_set", "shell_grants", "shell_grant_remove", "notification_mute", "model_load",
        "model_unload",
        // Lane T: goal editing, an agent in full, a view's history and Stop, and exports.
        "goal_criterion_edit", "goal_step_add", "goal_step_edit", "goal_step_block", "agent_get", "artifact_history",
        "artifact_stop", "export_preview", "export_render", "export_cancel", "export_discard", "export_list",
        "export_get",
    ]
    public static let elevated: Set<String> = [
        "approve", "approve_simple", "setting", "remote.keep_awake", "job_create", "job_resume", "storage_purge_chat",
        "memory_delete",  // lane Z: forgetting is a deletion that can't be undone (contract 3.6)
        "terminal_propose", "run_held_accept", "run_held_finish", "model_handoff_approve", "process_input_human",
        "remote.folder_create", "rewind_apply", "screen_session_grant", "browser_start",
        "quiz_share",  // lane Q: remote_policy.py's OPEN_ON_MAC, so always Face ID
        "memory_clear", "extension_toggle", "storage_trash_all", "storage_purge_all", "shell_grant_remove",  // lane S
    ]

    public init(
        pace: Double = 1, autoplay: Bool = true, now: @escaping @Sendable () -> Date = { Date() },
        sleeper: Sleeper? = nil
    ) {
        (updates, continuation) = AsyncStream.makeStream(of: ClientUpdate.self, bufferingPolicy: .unbounded)
        self.pace = max(0, pace)
        self.now = now
        self.sleeper = sleeper ?? { try await Task.sleep(for: $0) }
        self.autoplay = autoplay
        let seed = DemoData.seed(now: now())
        chats = seed.chats
        runs = Dictionary(uniqueKeysWithValues: seed.runs.map { ($0.id, $0) })
        activeChat = DemoData.loginChat
        activeRun = DemoData.loginRun
        settings = [
            "theme": "system", "reduced_motion": false, "stealth": false, "memory_enabled": true,
            "permissions": DemoData.permissions, "fast_replies": "long_tasks",
            "companion": ["pointer": true, "reactions": true, "status_words": "rotate", "ui_guidance": true],
            "git_decisions": ["force_push": true, "delete_remote_branch": true, "repository_identity": true, "clean": true],
            "memory_layers": [
                "working": true, "episodic": true, "semantic": true, "procedural": true, "temporal": true, "profile": true,
            ],
        ]
        workflows = DemoWorkflows(now: now())
        memory = DemoMemory(now: now())
        views = DemoViews(now: now())  // lane G
        details = DemoDetails(now: now())
        exportsDemo = DemoExports(now: now())  // lane T
        activityItems = DemoViews.decorated(DemoData.activity(now: now()))  // lane G: the work view's cards
        macStatus = [
            "name": .string(DemoData.macName), "battery_percent": 84, "charging": true, "on_power": true,
            "keep_awake": true,
        ]
    }

    /// The Mac the demo pretends to be paired with.
    public static func pairedMac(at date: Date = Date()) -> PairedMac {
        PairedMac(bridgeID: "demo", name: DemoData.macName, deviceID: "demo-iphone", pin: "demo", endpoints: [], pairedAt: date)
    }

    // MARK: - RemoteClient

    public func connect(to mac: PairedMac) async {
        guard !connected else { return }
        connected = true
        let resumed = everConnected
        everConnected = true
        continuation.yield(.status(ConnectionStatus(phase: .connecting, route: .demo)))
        continuation.yield(.status(ConnectionStatus(phase: .connected, route: .demo, roundTrip: 4, since: now())))
        continuation.yield(
            .welcome(
                BridgeInfo(
                    bridgeVersion: "demo", macName: DemoData.macName, pebbleRunning: true, pebbleVersion: DemoData.version,
                    methods: Self.methods, elevated: Self.elevated, resumed: resumed,
                    unlockSeconds: RemoteContract.defaultUnlockSeconds)))
        continuation.yield(.unlocked(until: unlockedUntil))
        for event in missed { continuation.yield(.event(event)) }
        missed = []
        if autoplay, runs[DemoData.loginRun]?.isLive == true, scripts[DemoData.loginRun] == nil {
            start(.login, run: DemoData.loginRun)
        }
    }

    public func disconnect() async {
        guard connected else { return }
        connected = false
        continuation.yield(.status(.idle))
    }

    public func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        guard connected else { throw RemoteCallError.notConnected }
        if !RemoteContract.readMethods.contains(method), (unlockedUntil ?? .distantPast) <= now() {
            grantUnlock()  // the client asks for Face ID itself when an action needs the unlock; in the demo it agrees
        }
        // Lane T: Create file takes a moment, as Pebble's does, so Cancel can reach it meanwhile.
        if method == "export_render" { return try await renderExport(params) }
        return try respond(method, params, proven: false)
    }

    /// One call; `proven` when it came with Face ID (an elevated call), which a new project folder and a terminal
    /// command need (proposal v0.5).
    private func respond(_ method: String, _ params: JSONValue, proven: Bool) throws -> JSONValue {
        switch method {
        case "state": return stateJSON()
        case "get_chat": return try chatJSON(try chatID(params), limit: nil)
        case "remote.chat_tail": return try chatJSON(try chatID(params), limit: params["limit"]?.int ?? 50)
        case "remote.chat_before": return try olderJSON(params)
        case "send": return try send(params)
        case "new_chat": return try newChat(workspace: params["workspace"]?.string, proven: proven)
        case "set_workspace": return try setWorkspace(params, proven: proven)
        case "attach_url": return try attachURL(params)
        case "terminal_propose": return try proposeCommand(params, proven: proven)
        case "remote.folders": return try folders.listing(params["path"]?.string)
        case "remote.folder_create": return try makeFolder(params, proven: proven)
        case "cancel": return try cancel(params)
        case "run_pause": return try pauseRun(params)
        case "run_resume": return try resumeRun(params)
        case "approve", "approve_simple": return try decide(params, approve: true, simpleOnly: method == "approve_simple")
        case "reject", "reject_simple": return try decide(params, approve: false, simpleOnly: method == "reject_simple")
        case "question_answer": return try answer(params)
        case "question_cancel": return try cancelQuestion(params)
        case "chat_rename": return try rename(params)
        case "storage_summary": return storageSummary()
        case "storage_trash_chat": return try trashChat(params)
        case "storage_restore_chat": return try restoreChat(params)
        case "storage_purge_chat": return try purgeChat(params)
        case "attach_bytes": return try attachBytes(params)
        case "remove_source":
            sources[params["id"]?.string ?? ""]?.removeAll { $0["id"] == params["source_id"] }
            return true
        case "run_list": return try runList(params)
        case "run_activity": return try runActivity(params)
        case "undo": return try undo(params)
        case "run_held_tests", "run_held_finish", "run_held_accept": return try held(method, params)
        case "run_readback": return try readback(params)
        case "run_reconcile": return try reconcile(params)
        case "process_list", "process_terminal", "process_read", "process_stop", "process_input_human", "process_inspect",
            "process_dismiss":
            return try process(method, params)
        case "model_handoff_preview", "model_handoff_approve", "model_handoff_start": return try handoff(method, params)
        case "chat_search": return search(params)
        case "remote.status":
            return [
                "mac": .object(macStatus), "pebble": ["running": true, "version": .string(DemoData.version)],
                "bridge": ["version": "demo", "epoch": "demo", "endpoints": []],
            ]
        case "remote.keep_awake":
            let on = params["on"]?.bool ?? false
            macStatus["keep_awake"] = .bool(on)
            emit("remote.mac", .object(macStatus.filter { $0.key != "name" }))
            return ["keep_awake": .bool(on)]
        case "remote.devices":
            let paired = JSONValue.double(now().timeIntervalSince1970 - 86400)
            return [
                [
                    "device_id": "demo-iphone", "name": "iPhone", "paired_at": paired,
                    "last_seen": .double(now().timeIntervalSince1970), "current": true,
                ]
            ]
        case "remote.revoke_device": return [:]
        case "remote.screenshot":
            // Contract C3: every display, or the one asked for; JPEG data, base64.
            let wanted = params["display"]?.int
            guard wanted == nil || wanted == 0 else { throw refusal("This Mac has no display \(wanted ?? 0).") }
            guard let jpeg = DemoScreen.jpeg() else { throw refusal("The demo couldn't draw its screen.") }
            return [
                "taken_at": .int(Int(now().timeIntervalSince1970 * 1000)),
                "displays": [
                    ["index": 0, "width": 1280, "height": 832, "format": "jpeg", "data": .string(jpeg.base64EncodedString())]
                ],
            ]
        case "remote.ping": return ["ts": params["ts"] ?? .null, "mac_ts": .int(Int(now().timeIntervalSince1970 * 1000))]
        // The composer's "/" commands and Settings › Memory (lane Z: DemoCommands, DemoMemory).
        case "command_catalogue": return DemoCommands.catalogueJSON
        case "memory_list": return try memory.list(params)
        case "memory_delete": return try memory.delete(params, taskRunning: activeRun != nil)
        case "memory_contests": return memory.contestsJSON()
        case "memory_resolve_contest": return try memory.resolve(params, taskRunning: activeRun != nil)
        default:
            if let answer = try settingsAnswer(method, params, proven: proven) { return answer }  // lane S
            if let answer = try detailsAnswer(method, params, proven: proven) { return answer }
            if let answer = try viewsAnswer(method, params) { return answer }  // lane G
            if let answer = try quizAnswer(method, params, proven: proven) { return answer }  // lane Q
            if let answer = try laneTAnswer(method, params) { return answer }  // lane T
            var titles: [String: String] = [:]
            for chat in chats where trashedAt[chat.id] == nil { titles[chat.id] = chat.title }
            if let answer = try workflows.handle(
                method, params, now: now(), chatTitles: titles, taskRunning: activeRun != nil, settings: &settings)
            {
                for event in answer.events { emit(event.name, event.data) }
                return answer.result
            }
            throw refusal("The demo can't do that. Pair with your Mac to use it.", code: BridgeErrorCode.notAllowed.rawValue)
        }
    }

    /// Face ID always agrees in the demo.
    public func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        guard connected else { throw RemoteCallError.notConnected }
        grantUnlock()  // every elevated call counts as an unlock (C1)
        return try respond(method, params, proven: true)
    }

    public func unlock(reason: String) async throws {
        guard connected else { throw RemoteCallError.notConnected }
        grantUnlock()
    }

    private func grantUnlock() {
        unlockedUntil = now().addingTimeInterval(Double(RemoteContract.defaultUnlockSeconds))
        continuation.yield(.unlocked(until: unlockedUntil))
    }

    public func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        Self.pairedMac(at: now())
    }

    // MARK: - Scripts

    enum Script: Sendable {
        case login
        case newTask(text: String)
        case approved(chat: String, action: String)
        case rejected(chat: String)
        case answered(tone: String)
        case resumed
        case stopping(outcome: String)
        /// A run that goes on with its reply (a held task Pebble finishes, a resumed one).
        case continued(text: String, seconds: Double)
        /// The new run of a model handoff, in its new conversation.
        case handedOff
    }

    func start(_ script: Script, run: String) {
        scripts[run]?.cancel()
        scripts[run] = Task { [weak self] in
            await self?.play(script, run: run)
        }
    }

    private func play(_ script: Script, run: String) async {
        do {
            switch script {
            case .login: try await playLogin(run)
            case .newTask(let text): try await playNewTask(run, text: text)
            case .approved(let chat, let action): try await playApproved(run, chat: chat, action: action)
            case .rejected: try await playContinuation(run, text: DemoData.readmeAfterRejection, seconds: 3.1)
            case .answered(let tone): try await playAnswered(run, tone: tone)
            case .resumed: try await playContinuation(run, text: "\n\nPicking up where I left off. Done now.", seconds: 4.0)
            case .stopping(let outcome): try await playStopping(run, outcome: outcome)
            case .continued(let text, let seconds): try await playContinuation(run, text: text, seconds: seconds)
            case .handedOff: try await playHandedOff(run)
            }
        } catch {
            // Stopped or replaced: whoever cancelled it says how the run ended.
        }
    }

    private func playLogin(_ run: String) async throws {
        try await wait(1.2)
        // Lane G: each step carries its card, and the plan moves as UpdatePlan would move it.
        let cards = DemoViews.loginViews
        emitPlan(run, done: 0)
        try await step(run, "Reading src/auth/session.ts", tool: "Read", seconds: 0.9, view: cards[0])
        try await step(run, "Searching for “redirect” in src", tool: "Grep", seconds: 0.8, view: cards[1])
        try await step(run, "Reading src/routes/login.tsx", tool: "Read", seconds: 0.7, view: cards[2])
        emitPlan(run, done: 2)
        try await step(run, "Editing src/auth/session.ts", tool: "Edit", seconds: 1.1, view: cards[3])
        emitPlan(run, done: 3)
        try await step(run, "Running the tests (npm test)", tool: "RunTests", seconds: 2.2, view: cards[4])
        emitPlan(run, done: 4)
        try await stream(run, DemoData.loginReply)
        finish(run, seconds: 14.2)
    }

    private func playNewTask(_ run: String, text: String) async throws {
        try await wait(0.4)
        setState(run, "running")
        guard let chat = runs[run].flatMap({ chatIndex($0.chatID) }) else { return }
        if chats[chat].id == DemoData.deployChat {  // lane G: Pebble asks with a form
            try await playDeployForm(run, chat: chats[chat].id)
            return
        }
        if chats[chat].workspace != nil {
            try await step(run, "Listing the project's files", tool: "Glob", seconds: 0.6)
            try await step(run, "Reading README.md", tool: "Read", seconds: 0.8)
        } else {
            try await step(run, "Searching the web", tool: "WebSearch", seconds: 1.0)
        }
        let topic = text.count > 60 ? String(text.prefix(57)) + "…" : text
        let reply = """
            This is the demo, so there's no Mac behind me. With your Mac paired, I'd work on “\(topic)” now: read \
            the project, make the change, run its tests, and ask you before anything risky.

            Meanwhile, try the waiting card in “Update the README for 2.0”, or answer the question in “Plan the \
            onboarding emails”.
            """
        try await stream(run, reply)
        finish(run, seconds: 6.4)
    }

    private func playApproved(_ run: String, chat: String, action: String) async throws {
        try await wait(0.9)
        updateAction(chat: chat, action: action) { card in
            card.status = "applied"
            if case .object(var payload) = card.payload {
                payload["result"] = Self.commandResult(payload["command"]?.string ?? payload["recipe"]?.string ?? "")
                card.payload = .object(payload)
            }
        }
        if runs[run]?.state == "waiting_approval" {
            // The held task's tests pass and it ends verified; the README's go on as before.
            let held = chat == DemoData.themeChat
            try await playContinuation(
                run, text: held ? DemoData.themeAfterTests : DemoData.readmeAfterApproval, seconds: held ? 6.2 : 4.8)
        }
    }

    private func playAnswered(_ run: String, tone: String) async throws {
        setState(run, "queued")
        try await wait(0.3)
        setState(run, "running")
        try await wait(0.6)
        progress(run, "Drafting the emails", kind: "working")
        try await wait(1.0)
        try await stream(run, "\n\n" + DemoData.emailsReply(tone: tone))
        finish(run, seconds: 9.5)
    }

    /// A run that waited goes on: its reply continues under the same message, as Pebble's resumed runs do.
    private func playContinuation(_ run: String, text: String, seconds: Double) async throws {
        setState(run, "queued")
        try await wait(0.3)
        setState(run, "running")
        try await wait(0.5)
        try await stream(run, text)
        finish(run, seconds: seconds)
    }

    /// Stop and Pause: the reply so far is kept, then the run settles and the worker comes free (runner.py).
    private func playStopping(_ run: String, outcome: String) async throws {
        try await wait(0.3)
        guard let record = runs[run], record.isLive else { return }
        let answer = answers[run] ?? ""
        if !answer.isEmpty { storeMessage(chat: record.chatID, role: "assistant", content: answer, id: record.messageID, run: run) }
        emit("stopped", ["chat_id": .string(record.chatID), "id": .string(record.messageID)])
        // Pebble's active seconds for the whole run: those before, plus this live stretch, which began at `running`
        // (its last state change). A resumed run then counts on from here, as on the Mac (UX audit U-23).
        setState(run, outcome, elapsed: record.elapsed + max(0, now().timeIntervalSince(record.updated)))
        answers[run] = nil
        emit("idle", ["chat_id": .string(record.chatID), "run_id": .string(run)])
    }

    // MARK: - Script steps

    func wait(_ seconds: Double) async throws {
        if pace > 0 {
            try await sleeper(.milliseconds(Int(seconds * pace * 1000)))
        } else {
            await Task.yield()
        }
        try Task.checkCancellation()
    }

    /// One tool call: its working line, then its done line. With a `view` (lane G), Pebble's own item also goes out as
    /// an `activity` event (C4) carrying the step's card, running then done.
    func step(_ run: String, _ label: String, tool: String, seconds: Double, view: JSONValue? = nil) async throws {
        progress(run, label, kind: "working", tool: tool)
        let seq = ((activityItems[run]?.count ?? 0) + 1) * 64
        let at = runs[run].map { now().timeIntervalSince($0.created) } ?? 0
        var running: [String: JSONValue] = [
            "seq": .int(seq), "at": .double(at), "kind": "tool", "label": .string(label), "detail": .null, "duration": .null,
            "status": "running",
        ]
        if let view {
            running["view"] = DemoViews.running(view)
            running["activity"] = StatusKey.classify(tool: tool, kind: "working").map { .string($0.rawValue) } ?? .null
        }
        activityItems[run, default: []].append(.object(running))
        if view != nil { emitActivity(run, .object(running)) }
        try await wait(seconds)
        if let index = activityItems[run]?.lastIndex(where: { $0["seq"]?.int == seq }), case .object(var item)? = activityItems[run]?[index] {
            item["status"] = "done"
            item["duration"] = .double(seconds)
            if let view { item["view"] = view }
            activityItems[run]?[index] = .object(item)
            if view != nil { emitActivity(run, .object(item)) }
        }
        progress(run, label, kind: "done", tool: tool)
        try await wait(0.25)
    }

    func stream(_ run: String, _ text: String) async throws {
        for piece in Self.tokens(text) {
            try await wait(0.035)
            guard let record = runs[run], record.isLive else { throw CancellationError() }
            answers[run, default: ""] += piece
            emit("token", ["chat_id": .string(record.chatID), "id": .string(record.messageID), "text": .string(piece)])
        }
    }

    /// The reply is stored, its usage and `complete` go out, the run settles, Pebble's banner, then the worker is free.
    func finish(_ run: String, seconds: Double) {
        guard let record = runs[run], record.isLive else { return }
        let index = chatIndex(record.chatID)
        let stored = index.flatMap { chats[$0].messages.first { $0.id == record.messageID }?.content } ?? ""
        let written = answers[run] ?? ""
        let reply = stored.isEmpty ? written : stored + written
        storeMessage(chat: record.chatID, role: "assistant", content: reply, id: record.messageID, run: run)
        emit(
            "usage",
            [
                "chat_id": .string(record.chatID), "id": .string(record.messageID),
                "usage": [
                    "input_tokens": 18_204, "output_tokens": .int(max(1, reply.count / 4)), "cached_tokens": 12_288,
                    "tokens_per_second": 41.5, "calls": 3, "route": "model", "seconds": .double(seconds),
                ],
            ])
        emit("complete", ["chat_id": .string(record.chatID), "id": .string(record.messageID), "seconds": .double(seconds)])
        answers[run] = nil
        setState(run, "completed", elapsed: record.elapsed + seconds)
        let title = index.map { chats[$0].title } ?? ""
        emit(
            "reply_banner",
            ["chat_id": .string(record.chatID), "run_id": .string(run), "title": "Pebble finished", "body": .string(title)])
        emit("idle", ["chat_id": .string(record.chatID), "run_id": .string(run)])
    }

    private func progress(_ run: String, _ label: String, kind: String, tool: String? = nil) {
        guard let record = runs[run] else { return }
        var data: [String: JSONValue] = [
            "chat_id": .string(record.chatID), "run_id": .string(run), "label": .string(label), "kind": .string(kind),
        ]
        if let tool { data["tool"] = .string(tool) }
        data["activity"] = StatusKey.classify(tool: tool, kind: kind).map { .string($0.rawValue) } ?? .null
        if kind == "working" { runs[run]?.steps += 1 }
        emit("progress", .object(data))
    }

    func setState(_ run: String, _ state: String, elapsed: Double? = nil) {
        guard var record = runs[run] else { return }
        record.state = state
        record.updated = now()
        if record.isLive { record.error = nil }  // a new live stretch: the old note no longer says how it ended
        if let elapsed { record.elapsed = elapsed }
        runs[run] = record
        if record.isLive {
            activeChat = record.chatID
            activeRun = run
        } else if activeRun == run {
            activeChat = nil
            activeRun = nil
        }
        if let index = chatIndex(record.chatID) { chats[index].updated = now() }
        var data: [String: JSONValue] = ["chat_id": .string(record.chatID), "run_id": .string(run), "state": .string(state)]
        if let elapsed { data["elapsed"] = .double(elapsed) }
        emit("run", .object(data))
    }

    func emit(_ name: String, _ data: JSONValue) {
        seq += 1
        let event = PebbleEvent(seq: seq, name: name, data: data, time: now())
        sent.append(event)
        if sent.count > 2000 { sent.removeFirst(sent.count - 2000) }
        if connected {
            continuation.yield(.event(event))
        } else {
            missed.append(event)
        }
    }

    // MARK: - Calls

    func send(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard let text = params["text"]?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.utf8.count <= 100_000
        else { throw refusal("Enter a message under 100 KB.") }
        guard chatIndex(chat) != nil else { throw refusal("Conversation not found.") }
        if trashedAt[chat] != nil {
            throw refusal(
                "This conversation is in Recently deleted. Restore it in Settings -> Data & storage to keep using it.",
                code: "trashed_conversation")
        }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = Set((params["source_ids"]?.array ?? []).compactMap(\.string))
        if !wanted.isEmpty && words.hasPrefix("/") { throw refusal("Slash commands don't take attachments. Attach them to a new task.") }
        if !wanted.isEmpty && activeChat == chat {
            throw refusal("Follow-up input during a run accepts text only. Attach sources to a new task.")
        }
        let selected = (sources[chat] ?? []).filter { wanted.contains($0["id"]?.string ?? "") }
        if selected.contains(where: { $0["kind"]?.string == "image" }), workflows.profile == "default-local" {
            throw refusal(
                "Choose a vision-capable online model to send images. This local text-only model cannot view screenshots.")
        }
        if words.hasPrefix("/") {
            // A slash command is answered at once: both messages stored, then only `complete` (Pebble's app.send). A name
            // that isn't in Pebble's catalogue is refused, as Pebble refuses it (lane Z, DemoCommands).
            guard DemoCommands.knows(words) else { throw refusal(DemoCommands.unknown) }
            let command = storeMessage(chat: chat, role: "user", content: words, id: "cmd-" + nextID())
            let answer = DemoCommands.reply(words, memory: memory)
            let reply = storeMessage(chat: chat, role: "assistant", content: answer, id: "cmd-" + nextID())
            emit("complete", ["chat_id": .string(chat), "id": .string(reply), "seconds": 0])
            return ["message_id": .string(command), "command": true]
        }
        if let activeChat, let activeRun {
            guard activeChat == chat else { throw refusal("One task can run at a time on this device.") }
            // Guidance for the working run: kept in the conversation and queued for the run.
            let message = storeMessage(chat: chat, role: "user", content: words)
            return [
                "message_id": .string(message), "input_id": .string(nextID()), "run_id": .string(activeRun),
                "status": "queued", "steering": true,
            ]
        }
        let run = "r-" + nextID()
        runs[run] = DemoRun(
            id: run, chatID: chat, state: "queued", steps: 0, elapsed: 0, error: nil, created: now(), updated: now(),
            messageID: "m-" + nextID())
        let message = storeMessage(chat: chat, role: "user", content: words)
        if let index = chatIndex(chat), let position = chats[index].messages.firstIndex(where: { $0.id == message }) {
            // Photos and files stay with the message; a web page is read as source material, which Pebble's get_chat
            // doesn't list with the message.
            chats[index].messages[position].attachments = selected.filter { $0["kind"]?.string != "url" }.map { chip in
                .object((chip.object ?? [:]).merging(["message_id": .string(message)]) { _, new in new })
            }
        }
        sources[chat] = nil  // the selected go with the message; Pebble drops the rest
        setState(run, "queued")
        start(.newTask(text: words), run: run)
        return ["message_id": .string(message), "run_id": .string(run)]
    }

    /// new_chat in Companion, in a project a conversation uses, or (with Face ID) in another folder of the demo Mac.
    private func newChat(workspace: String?, proven: Bool) throws -> JSONValue {
        let path = workspace.flatMap { $0.isEmpty ? nil : $0 }
        if let path { try checkFolder(path, proven: proven) }
        let chat = DemoChat(id: "c-" + nextID(), title: "New conversation", workspace: path, updated: now())
        chats.append(chat)
        return (try? chatJSON(chat.id, limit: nil)) ?? chat.rowJSON
    }

    // MARK: - Projects (proposal v0.5, with Pebble's own refusals)

    /// The bridge's rule for a project folder (the mock's, lane C2): a folder a conversation uses needs nothing more; a
    /// folder no conversation uses widens what Pebble may read, so it needs Face ID, and must be one `remote.folders`
    /// lists. Pebble refuses the home folder itself.
    private func checkFolder(_ path: String, proven: Bool) throws {
        if path == DemoFolders.home {
            throw refusal("Choose a project folder rather than your home folder or disk root.")
        }
        guard !chats.contains(where: { $0.workspace == path && trashedAt[$0.id] == nil }) else { return }
        // A folder made from this phone a moment ago counts as known (proposal v0.6): the unlock is enough.
        guard proven || folders.wasMadeRecently(path, at: now()) else {
            throw refusal("Confirm with Face ID to do this.", code: BridgeErrorCode.proofRequired.rawValue)
        }
        guard folders.contains(path) else {
            throw refusal(
                "Choose a folder from the list. Pebble Remote can't connect that one.",
                code: BridgeErrorCode.notAllowed.rawValue)
        }
    }

    /// set_workspace: a conversation moves into a project, or back to Companion (path null).
    private func setWorkspace(_ params: JSONValue, proven: Bool) throws -> JSONValue {
        let chat = try chatID(params)
        guard let index = chatIndex(chat) else { throw refusal("Conversation not found.") }
        let path = params["path"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        if let path { try checkFolder(path, proven: proven) }
        if activeRun != nil { throw refusal("Stop the current task before changing its project.") }
        chats[index].workspace = path
        return try chatJSON(chat, limit: nil)
    }

    /// attach_url: Pebble reads a public page as source material for the next message (the demo only pretends).
    private func attachURL(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard chatIndex(chat) != nil else { throw refusal("Conversation not found.") }
        guard settings["permissions"]?["tools"]?["web"]?.bool != false else {
            throw refusal("Web access is disabled in Permissions.")
        }
        let url = (params["url"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteStore.isReadableWebAddress(url) else {
            throw refusal("Enter a public https:// URL without credentials or a custom port.")
        }
        guard (sources[chat]?.count ?? 0) < 10 else { throw refusal("Use up to ten sources per message.") }
        let id = "src-" + nextID()
        let characters = 1_800 + 7 * url.count
        sources[chat, default: []].append(
            ["id": .string(id), "name": .string(url), "kind": "url", "characters": .int(characters)])
        return ["id": .string(id), "name": .string(url), "characters": .int(characters)]
    }

    /// terminal_propose: one command in the conversation's project. Pebble's review holds it as a card; the demo never
    /// runs anything, and approving the card shows a pretend result.
    private func proposeCommand(_ params: JSONValue, proven: Bool) throws -> JSONValue {
        guard proven else { throw refusal("Confirm with Face ID to do this.", code: BridgeErrorCode.proofRequired.rawValue) }
        let chat = try chatID(params)
        guard let index = chatIndex(chat) else { throw refusal("Conversation not found.") }
        if activeRun != nil { throw refusal("Wait for the current task before starting a terminal command.") }
        guard let root = chats[index].workspace else { throw refusal("Choose a project folder for this conversation first.") }
        let command = (params["command"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw refusal("Enter a command.") }
        let card = DemoAction(
            id: "a-" + nextID(), chatID: chat, kind: "command", status: "pending",
            payload: [
                "command": .string(command), "root": .string(root), "risk": "Terminal command",
                "network": .bool(params["network"]?.bool ?? false), "writable": false,
            ], created: now())
        chats[index].actions.append(card)
        chats[index].updated = now()
        emit("actions", ["chat_id": .string(chat), "actions": .array(chats[index].actions.map(\.json))])
        return ["status": "pending", "action_id": .string(card.id)]
    }

    /// What an approved command printed, in the demo.
    static func commandResult(_ command: String) -> JSONValue {
        switch command {
        case "npm test":
            return ["output": "> pebble-docs@2.0.0 test\n> node --test\n\n# tests 42\n# pass 42\n# fail 0", "exit_code": 0]
        case _ where command.hasPrefix("git status"):
            return ["output": " M src/auth/session.ts\n?? notes/redirects.md", "exit_code": 0]
        default:
            return ["output": "This is the demo, so nothing ran. With your Mac paired, the output shows here.", "exit_code": 0]
        }
    }

    // MARK: - Recently deleted (data_mirror.py)

    func storageSummary() -> JSONValue {
        let list = trashedAt.sorted { $0.value > $1.value }.compactMap { id, at -> JSONValue? in
            guard let chat = chats.first(where: { $0.id == id }) else { return nil }
            return [
                "chat_id": .string(id), "title": .string(chat.title), "deleted": .double(at.timeIntervalSince1970),
                "origin": "app", "delete_after": .double(at.timeIntervalSince1970 + 2_592_000),
            ]
        }
        var summary: [String: JSONValue] = ["recently_deleted": .array(list), "available": true]
        summary.merge(settingsDemo.storageParts(now: now())) { $1 }  // lane S: changes from files, waiting deletions
        return .object(summary)
    }

    private func trashChat(_ params: JSONValue) throws -> JSONValue {
        guard let id = params["chat_id"]?.string, chatIndex(id) != nil else { throw refusal("Conversation not found.") }
        if activeChat == id { throw refusal("It is running a task.") }
        let at = now()
        trashedAt[id] = at
        emit("storage", ["changed": "recently_deleted"])
        return ["trashed": .string(id), "delete_after": .double(at.timeIntervalSince1970 + 2_592_000)]
    }

    private func restoreChat(_ params: JSONValue) throws -> JSONValue {
        guard let id = params["chat_id"]?.string, chatIndex(id) != nil else { throw refusal("Conversation not found.") }
        guard trashedAt.removeValue(forKey: id) != nil else { throw refusal("That conversation is not in Recently deleted.") }
        emit("storage", ["changed": "recently_deleted"])
        return ["restored": .string(id)]
    }

    private func purgeChat(_ params: JSONValue) throws -> JSONValue {
        guard params["confirm"]?.bool == true else { throw refusal("Confirm the deletion first.") }
        guard let id = params["chat_id"]?.string, trashedAt[id] != nil else {
            throw refusal("That conversation is not in Recently deleted.")
        }
        trashedAt[id] = nil
        chats.removeAll { $0.id == id }
        for (run, record) in runs where record.chatID == id {
            runs[run] = nil
            activityItems[run] = nil
        }
        emit("storage", ["changed": "deleted", "chat_id": .string(id), "deleted_artifacts": []])
        emit("storage", ["changed": "recently_deleted"])
        return ["deleted": .string(id)]
    }

    // MARK: - Photos and files (attachments.py attach_bytes)

    private func attachBytes(_ params: JSONValue) throws -> JSONValue {
        guard let chat = params["id"]?.string, chatIndex(chat) != nil else { throw refusal("Conversation not found.") }
        guard let text = params["data_base64"]?.string, text.count <= 96_000 else {
            throw refusal("Send pasted data in base64 chunks of at most 96,000 characters.")
        }
        guard let offset = params["offset"]?.int, offset >= 0, let final = params["final"]?.bool else {
            throw refusal("Choose a non-negative byte offset and a final flag.")
        }
        guard let piece = Data(base64Encoded: text) else { throw refusal("The pasted data is not valid base64.") }
        var upload = (chat: chat, name: params["name"]?.string ?? "", data: Data())
        if let token = params["upload"]?.string {
            guard let known = uploads[token], known.chat == chat else { throw refusal("This paste is no longer in progress. Paste again.") }
            upload = known
            uploads[token] = nil
        } else if (sources[chat]?.count ?? 0) >= 10 {
            throw refusal("Use up to ten attachments per message.")
        }
        guard offset == upload.data.count else { throw refusal("Parts of this paste arrived out of order. Paste again.") }
        upload.data.append(piece)
        guard upload.data.count <= 50_000_000 else { throw refusal("Use a file smaller than 50 MB.") }
        if !final {
            let token = "upload-" + nextID()
            uploads[token] = upload
            return ["upload": .string(token), "received": .int(upload.data.count)]
        }
        guard !upload.data.isEmpty else { throw refusal("Nothing was pasted.") }
        let isImage = upload.data.starts(with: [0xFF, 0xD8]) || upload.data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            || ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp"].contains((upload.name as NSString).pathExtension.lowercased())
        let id = "src-" + nextID()
        let chip: JSONValue
        if isImage {
            let preview = (upload.data.starts(with: [0xFF, 0xD8]) && upload.data.count < 200_000 ? upload.data : DemoScreen.jpeg(width: 96, height: 64)) ?? Data()
            chip = [
                "id": .string(id), "name": .string(upload.name.isEmpty ? "Pasted image.png" : upload.name), "kind": "image",
                "preview": .string("data:image/jpeg;base64," + preview.base64EncodedString()), "characters": 0,
                "bytes": .int(upload.data.count),
            ]
        } else {
            chip = [
                "id": .string(id), "name": .string(upload.name.isEmpty ? "Pasted file" : upload.name), "kind": "file",
                "bytes": .int(upload.data.count), "notice": "", "message_id": .null, "characters": 0,
            ]
        }
        sources[chat, default: []].append(chip)
        return chip
    }

    // MARK: - Runs in detail

    private func runList(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard chatIndex(chat) != nil else { throw refusal("Conversation not found.") }
        return .array(runs.values.filter { $0.chatID == chat }.sorted { $0.created > $1.created }.prefix(100).map(\.json))
    }

    private func runActivity(_ params: JSONValue) throws -> JSONValue {
        guard let run = params["run_id"]?.string, let record = runs[run] else {
            throw refusal("Run not found in this conversation.")
        }
        guard let after = params["after"]?.int ?? Optional(0), after >= 0 else {
            throw refusal("Use a nonnegative whole activity cursor.")
        }
        let items = (activityItems[run] ?? []).filter { ($0["seq"]?.int ?? 0) > after || $0["status"]?.string == "running" }
        let next = max(after, items.compactMap { $0["seq"]?.int }.max() ?? 0)
        // A live run's time runs on from its last update, as Pebble's own reply counts it (run_activity.py `_elapsed`):
        // the record's seconds alone stood still between state changes, so Details said "2 s" a minute in (U-58).
        let elapsed = record.isLive ? record.elapsed + max(0, now().timeIntervalSince(record.updated)) : record.elapsed
        // Lane G: the work view's header and, once the run settled, its summary (work_view.header and summary).
        let receipt = DemoViews.receipt(
            items: activityItems[run] ?? [], state: record.state, elapsed: elapsed, plan: views.plans[run])
        return [
            "run_id": .string(run), "state": .string(record.state), "started": .double(record.created.timeIntervalSince1970),
            "elapsed": .double(elapsed), "items": .array(items),
            "reasoning": ["available": .bool(DemoData.reasoning[run] != nil), "text": .string(DemoData.reasoning[run] ?? "")],
            "usage": .null, "next": .int(next), "header": receipt.header, "summary": receipt.summary,
        ]
    }

    private func cancel(_ params: JSONValue) throws -> JSONValue {
        let chat = params["id"]?.string
        let run = params["run_id"]?.string
        if let chat, let activeChat, activeChat != chat { throw refusal("Another conversation owns the active worker.") }
        guard let activeRun else {
            guard let chat else { return true }
            let held = runs.values.filter {
                $0.chatID == chat && ["waiting_input", "waiting_approval", "paused"].contains($0.state)
                    && (run == nil || run == $0.id)
            }.sorted { $0.created > $1.created }
            if let waiting = held.first {
                scripts[waiting.id]?.cancel()
                setState(waiting.id, "stopped")
            }
            return true
        }
        if let run, run != activeRun { throw refusal("This run is not active.") }
        start(.stopping(outcome: "stopped"), run: activeRun)
        return true
    }

    private func pauseRun(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        let run = params["run_id"]?.string
        guard activeChat == chat, let activeRun else {
            let held = runs.values.filter {
                $0.chatID == chat && ["waiting_input", "waiting_approval"].contains($0.state) && (run == nil || run == $0.id)
            }.sorted { $0.created > $1.created }
            guard let waiting = held.first else { throw refusal("This conversation has no active or waiting run.") }
            setState(waiting.id, "paused")
            return ["run_id": .string(waiting.id), "status": "paused"]
        }
        if let run, run != activeRun { throw refusal("This run does not own the active worker.") }
        start(.stopping(outcome: "paused"), run: activeRun)
        return ["run_id": .string(activeRun), "status": "pause_requested"]
    }

    private func resumeRun(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        if activeRun != nil { throw refusal("Stop the active run before resuming another one.") }
        let resumable: Set<String> = [
            "paused", "interrupted", "stopped", "failed", "budget_exhausted", "waiting_approval", "waiting_input",
            "verification_required",
        ]
        let candidates = runs.values.filter { $0.chatID == chat && resumable.contains($0.state) }.sorted { $0.created > $1.created }
        let run = params["run_id"]?.string.flatMap { runs[$0] } ?? candidates.first
        guard let run, run.chatID == chat else { throw refusal("This conversation has no resumable run.") }
        if let limits = params["limits"], !limits.isNull {
            // runtime.RunLimits.parse, with Pebble's words.
            guard let fields = limits.object, Set(fields.keys).isSubset(of: ["max_steps", "max_seconds"]) else {
                throw refusal("Run limits accept max_steps and max_seconds.")
            }
            let steps = fields["max_steps"]?.int ?? 64, seconds = fields["max_seconds"]?.double ?? 900
            guard (1...256).contains(steps), (1...86_400).contains(seconds) else {
                throw refusal("Choose 1\u{2013}256 steps and 1\u{2013}86400 seconds per run.")
            }
        }
        let index = chatIndex(chat)
        if let index, chats[index].actions.contains(where: { $0.status == "pending" }) {
            throw refusal("Resolve this run's pending actions before resuming it.")
        }
        if let index, chats[index].questions.contains(where: { $0.runID == run.id && $0.status == "pending" && $0.required }) {
            if run.state == "waiting_input" { throw refusal("Answer or cancel this run's required question first.") }
            setState(run.id, "waiting_input")
            return ["run_id": .string(run.id), "status": "waiting_input"]
        }
        start(.resumed, run: run.id)
        return ["run_id": .string(run.id), "status": "queued"]
    }

    private func decide(_ params: JSONValue, approve: Bool, simpleOnly: Bool) throws -> JSONValue {
        let chat = try chatID(params)
        guard let action = params["action_id"]?.string, let index = chatIndex(chat),
            let card = chats[index].actions.first(where: { $0.id == action }), card.status == "pending"
        else { throw refusal("This action is no longer awaiting approval.") }
        if simpleOnly && !CardKind(rawValue: card.kind).isSimple { throw refusal("Review this one in the workspace.") }
        if approve {
            if activeRun != nil { throw refusal("Wait for the current task to finish before approving an action.") }
            updateAction(chat: chat, action: action) { $0.status = "running" }
            let owner = runs.values.first { $0.chatID == chat && $0.state == "waiting_approval" }?.id
            start(.approved(chat: chat, action: action), run: owner ?? "card-" + action)
            return true
        }
        updateAction(chat: chat, action: action) { $0.status = "rejected" }
        if let owner = runs.values.first(where: { $0.chatID == chat && $0.state == "waiting_approval" })?.id {
            start(.rejected(chat: chat), run: owner)
        }
        return true
    }

    private func answer(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard let id = params["question_id"]?.string, let index = chatIndex(chat),
            let position = chats[index].questions.firstIndex(where: { $0.id == id })
        else { throw refusal("Question not found in this conversation.") }
        var question = chats[index].questions[position]
        guard params["revision"]?.int == question.revision else {
            throw refusal("This question revision is stale. Refresh it before answering.")
        }
        guard question.status == "pending" else { throw refusal("This question is no longer accepting answers.") }
        let items = question.items.array ?? []
        guard let answers = params["answers"]?.object,
            Set(answers.keys) == Set(items.compactMap { $0["id"]?.string })
        else { throw refusal("Answer each requested question exactly once.") }
        var canonical: [String: JSONValue] = [:]
        var said: [String] = []
        for item in items {
            guard let itemID = item["id"]?.string, let given = answers[itemID]?.object else { continue }
            if Set(given.keys) == ["option_id"], let optionID = given["option_id"]?.string {
                guard let option = item["options"]?.array?.first(where: { $0["id"]?.string == optionID }),
                    let label = option["label"]?.string
                else { throw refusal("Choose an offered option or use free text.") }
                canonical[itemID] = ["option_id": .string(optionID), "text": .string(label)]
                said.append(label)
            } else if Set(given.keys) == ["text"], let text = given["text"]?.string {
                let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !words.isEmpty, words.count <= 2000 else { throw refusal("Enter nonempty text under 2000 characters.") }
                canonical[itemID] = ["text": .string(words)]
                said.append(words)
            } else {
                throw refusal("Choose an option or enter free text.")
            }
        }
        question.status = "answered"
        question.answer = .object(canonical)
        chats[index].questions[position] = question
        let words = said.joined(separator: "\n")
        let message = JSONValue.object(["id": .string("answer-" + id), "role": "user", "content": .string(words)])
        storeMessage(chat: chat, role: "user", content: words, id: "answer-" + id)
        let result: JSONValue = [
            "question_id": .string(id), "run_id": .string(question.runID), "status": "answered", "message": message,
        ]
        emit(
            "question",
            [
                "chat_id": .string(chat), "question_id": .string(id), "run_id": .string(question.runID),
                "status": "answered", "message": message, "question": question.json,
            ])
        if runs[question.runID]?.state == "waiting_input" { start(.answered(tone: said.first ?? words), run: question.runID) }
        return result
    }

    private func cancelQuestion(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        guard let id = params["question_id"]?.string, let index = chatIndex(chat),
            let position = chats[index].questions.firstIndex(where: { $0.id == id }),
            params["revision"]?.int == chats[index].questions[position].revision
        else { throw refusal("Question not found or revision is stale.") }
        var question = chats[index].questions[position]
        guard question.status == "pending" else { throw refusal("This question is no longer pending.") }
        question.status = "cancelled"
        chats[index].questions[position] = question
        emit(
            "question",
            [
                "chat_id": .string(chat), "question_id": .string(id), "run_id": .string(question.runID),
                "status": "cancelled", "required": .bool(question.required), "question": question.json,
            ])
        if question.required, runs[question.runID]?.state == "waiting_input" { setState(question.runID, "stopped") }
        return [
            "question_id": .string(id), "run_id": .string(question.runID), "status": "cancelled",
            "required": .bool(question.required),
        ]
    }

    private func rename(_ params: JSONValue) throws -> JSONValue {
        let chat = try chatID(params)
        let title = (params["title"]?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !title.isEmpty else { throw refusal("Enter a name for the conversation.") }
        guard let index = chatIndex(chat) else { throw refusal("Conversation not found.") }
        chats[index].title = String(title.prefix(200))
        return ["id": .string(chat), "title": .string(chats[index].title)]
    }

    private func search(_ params: JSONValue) -> JSONValue {
        let words = (params["query"]?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard words.count >= 2 else { return ["query": .string(words), "matches": []] }
        var matches: [JSONValue] = []
        for chat in chats.sorted(by: { $0.updated > $1.updated }) {
            guard let message = chat.messages.last(where: { $0.content.localizedCaseInsensitiveContains(words) }) else { continue }
            let excerpt = message.content.split(whereSeparator: \.isNewline).joined(separator: " ")
            matches.append(["id": .string(chat.id), "excerpt": .string(String(excerpt.prefix(120)))])
        }
        return ["query": .string(words), "matches": .array(Array(matches.prefix(30)))]
    }

    // MARK: - What Pebble answers with

    private func stateJSON() -> JSONValue {
        let listed = chats.filter { (!$0.messages.isEmpty || !$0.actions.isEmpty) && trashedAt[$0.id] == nil }
            .sorted { $0.updated > $1.updated }
        let settingsObject = settings
        return [
            "job_notifications": .array(workflows.notices),
            "chats": .array(listed.map(\.rowJSON)),
            "model": workflows.modelStatus(),
            "guard": ["available": true, "error": .null],
            "active": activeChat.map(JSONValue.string) ?? .null,
            "active_run": activeRun.map(JSONValue.string) ?? .null,
            "runs": .array(runs.values.sorted { $0.created > $1.created }.prefix(100).map(\.json)),
            "settings": .object(settingsObject),
            "platform": "darwin",
            "version": .string(DemoData.version),
            "profiles": .array(workflows.profiles()),
            // Each memory layer with its count (memory.py `stats`; lane Z).
            "memory": memory.stats(
                enabled: settingsObject["memory_enabled"]?.bool ?? true, layers: settingsObject["memory_layers"]),
        ]
    }

    /// get_chat's shape; with `limit` (remote.chat_tail) only the newest messages, plus has_older.
    private func chatJSON(_ id: String, limit: Int?) throws -> JSONValue {
        guard let index = chatIndex(id) else { throw refusal("Conversation not found.") }
        let chat = chats[index]
        let shown = limit.map { Array(chat.messages.suffix(max(1, $0))) } ?? chat.messages
        guard case .object(var object) = chat.rowJSON else { return chat.rowJSON }
        object["trashed"] = .bool(trashedAt[id] != nil)
        object["messages"] = .array(shown.map(\.json))
        object["actions"] = .array(chat.actions.map(\.json))
        object["artifacts"] = .array(views.list(in: id))  // lane G
        let ordered = runs.values.filter { $0.chatID == id }.sorted { $0.created > $1.created }
        object["runs"] = .array(ordered.enumerated().map { index, run in counted(run, newest: index < 20) })
        object["questions"] = .array(chat.questions.filter { $0.status == "pending" }.map(\.json))
        object["plan"] = .null
        if limit != nil { object["has_older"] = .bool(shown.count < chat.messages.count) }
        return .object(object)
    }

    /// A run as get_chat lists it: each settled run of the newest 20 carries the counts its end line shows, counted
    /// from its activity items as Pebble does (app.py `_run_counts`: tool, check and agent rows are steps, retry rows
    /// retries, approval durations the seconds waited), so the end line and Details › Activity agree (U-45).
    private func counted(_ run: DemoRun, newest: Bool) -> JSONValue {
        guard newest, !run.isLive, case .object(var object) = run.json else { return run.json }
        let items = activityItems[run.id] ?? []
        let kinds = items.compactMap { $0["kind"]?.string }
        let waited = items.filter { $0["kind"]?.string == "approval" }.compactMap { $0["duration"]?.double }.reduce(0, +)
        object["counts"] = [
            "steps": .int(kinds.filter { ["tool", "check", "child"].contains($0) }.count),
            "retries": .int(kinds.filter { $0 == "retry" }.count), "waited": .double((waited * 1000).rounded() / 1000),
        ]
        return .object(object)
    }

    private func olderJSON(_ params: JSONValue) throws -> JSONValue {
        let id = try chatID(params)
        guard let index = chatIndex(id) else { throw refusal("Conversation not found.") }
        let messages = chats[index].messages
        let before = params["before"]?.string
        let end = before.flatMap { b in messages.firstIndex { $0.id == b } } ?? messages.count
        let limit = max(1, params["limit"]?.int ?? 50)
        let start = max(0, end - limit)
        return ["messages": .array(messages[start..<end].map(\.json)), "has_older": .bool(start > 0)]
    }

    // MARK: - Helpers

    @discardableResult
    func storeMessage(chat: String, role: String, content: String, id: String? = nil, run: String? = nil) -> String {
        let id = id ?? "m-" + nextID()
        guard let index = chatIndex(chat) else { return id }
        if let existing = chats[index].messages.firstIndex(where: { $0.id == id }) {
            chats[index].messages[existing].content = content  // INSERT OR REPLACE
        } else {
            chats[index].messages.append(DemoMessage(id: id, role: role, content: content, created: now(), runID: run))
        }
        chats[index].updated = now()
        if role == "user", chats[index].title == "New conversation" {
            chats[index].title = String(content.prefix(54)).replacingOccurrences(of: "\n", with: " ")
        }
        return id
    }

    func updateAction(chat: String, action: String, _ change: (inout DemoAction) -> Void) {
        guard let index = chatIndex(chat), let position = chats[index].actions.firstIndex(where: { $0.id == action }) else { return }
        change(&chats[index].actions[position])
        emit("actions", ["chat_id": .string(chat), "actions": .array(chats[index].actions.map(\.json))])
    }

    func chatIndex(_ id: String) -> Int? { chats.firstIndex { $0.id == id } }

    func chatID(_ params: JSONValue) throws -> String {
        guard let id = params["id"]?.string else { throw refusal("Conversation not found.") }
        return id
    }

    func nextID() -> String {
        counter += 1
        return String(format: "demo%04d", counter)
    }

    func refusal(_ message: String, code: String? = nil) -> RemoteCallError {
        .refused(PersonFacingError(message: message, code: code))
    }

    /// A reply's words in small pieces, as a model streams them.
    static func tokens(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    static func commandReply(_ command: String) -> String {
        let name = command.dropFirst().split(separator: " ").first.map(String.init) ?? ""
        switch name {
        case "help":
            return "Commands: /new starts a conversation, /stop stops this conversation's task, /model shows the model, /effort shows the effort."
        case "model":
            return "Model: gpt-5.1 (ChatGPT), medium effort."
        default:
            return "There's no /\(name) command. /help lists them."
        }
    }
}

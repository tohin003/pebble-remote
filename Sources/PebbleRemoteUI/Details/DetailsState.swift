import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// What the conversation's Details screen has read from Pebble, tab by tab, and the reads behind it. The run's steps
/// need no unlock; every other read is made only while the phone may read quietly (`readsQuietly`), so opening Details
/// never asks for Face ID by itself. Reads the bridge records on the Mac (Context, Changes, agents, Pebble for Chrome)
/// are made when their tab is shown and on Refresh, never on a timer.
@MainActor
@Observable
final class DetailsState {
    let chatID: ChatID
    /// The task the screen is about: the conversation's working task when there is one, else the one it opened on.
    private(set) var runID: RunID?

    // Activity
    private(set) var steps: RunSteps?
    private(set) var stepsProblem: String?
    // Task
    private(set) var goals: [GoalSummary] = []
    private(set) var goal: GoalRecord?
    private(set) var agents: [AgentNode] = []
    private(set) var goalsRead = false
    private(set) var agentsRead = false
    // Context
    private(set) var context: ContextUse?
    private(set) var contextProblem: String?
    // Changes
    private(set) var rewind: RewindPlan?
    private(set) var rewindProblem: String?
    // Browser
    private(set) var chrome: ChromeStatus?
    private(set) var pebbleBrowser: PebbleBrowserStatus?
    private(set) var pebbleTabs: [BrowserTab] = []
    private(set) var browserProblem: String?

    /// A step the person asked for failed: Pebble's or the bridge's words, shown in this sheet.
    var notice: String?
    /// A step that worked, in Pebble's words ("Goal paused."), announced and shown under the tab's controls.
    var done: String?

    init(chatID: ChatID, runID: RunID?) {
        self.chatID = chatID
        self.runID = runID
    }

    var isShowingNotice: Bool {
        get { notice != nil }
        set { if !newValue { notice = nil } }
    }

    /// The task is working now (Pebble's live states).
    var runIsLive: Bool {
        guard let state = steps?.details.run.state else { return false }
        return Self.liveStates.contains(state.rawValue)
    }

    static let liveStates: Set<String> = ["queued", "running", "retry_wait"]

    // MARK: Reading

    /// What the tabs' listing needs: the steps, and, when quiet reads are allowed, the goals and this conversation's
    /// schedules and shared windows. A newer working task takes over the screen.
    func refresh(_ store: RemoteStore, liveRun: RunID?, newest: RunID? = nil) async {
        if let liveRun, liveRun != runID {
            runID = liveRun
            context = nil
            rewind = nil
            agents = []
            agentsRead = false
        } else if runID == nil, let newest {
            // Opened before the conversation had loaded (from Settings): the task it shows once it has.
            runID = newest
        }
        await loadSteps(store)
        guard store.readsQuietly else { return }
        await loadGoals(store)
        await store.loadTools(in: chatID)
    }

    func loadSteps(_ store: RemoteStore) async {
        guard let runID, store.bridgeOffers("run_activity") else { return }
        do {
            steps = try await store.runSteps(runID, in: chatID)
            stepsProblem = nil
        } catch {
            let words = store.takeNotice()
            if steps == nil { stepsProblem = words ?? AppCopy.Errors.generic }
        }
    }

    func loadGoals(_ store: RemoteStore) async {
        guard store.bridgeOffers("goal_list"), let list = try? await store.goals(in: chatID) else { return }
        goals = list
        goalsRead = true
        if let current = list.first(where: \.isCurrent), store.bridgeOffers("goal_get") {
            if let record = try? await store.goal(current.id, in: chatID) { goal = record }
        } else {
            goal = nil
        }
        _ = store.takeNotice()
    }

    func loadAgents(_ store: RemoteStore) async {
        guard let runID, store.bridgeOffers("agent_list") else { return }
        if let list = try? await store.agents(in: chatID, run: runID) {
            agents = list
            agentsRead = true
        }
        _ = store.takeNotice()
    }

    func loadContext(_ store: RemoteStore) async {
        guard store.bridgeOffers("context_inspect") else { return }
        do {
            context = try await store.contextUse(in: chatID, run: runID)
            contextProblem = nil
        } catch {
            contextProblem = store.takeNotice() ?? (context == nil ? AppCopy.Errors.generic : nil)
        }
    }

    /// The rewind plan for the conversation's latest settled task, at `step` (0 first: before the task).
    func loadRewind(_ store: RemoteStore, run: RunID, step: Int) async {
        do {
            rewind = try await store.rewindPreview(in: chatID, run: run, step: step)
            rewindProblem = nil
        } catch {
            rewindProblem = store.takeNotice() ?? AppCopy.Details.rewindNotReady
        }
    }

    func loadBrowser(_ store: RemoteStore) async {
        var problem: String?
        if store.bridgeOffers("browser_extension_status") {
            do { chrome = try await store.chromeStatus() } catch { problem = store.takeNotice() }
        }
        if store.bridgeOffers("browser_status") {
            do {
                let status = try await store.pebbleBrowserStatus()
                pebbleBrowser = status
                var tabs: [BrowserTab] = []
                if status.running, store.bridgeOffers("browser_tabs") {
                    tabs = (try? await store.pebbleBrowserTabs()) ?? []
                }
                pebbleTabs = tabs
                _ = store.takeNotice()
            } catch {
                problem = problem ?? store.takeNotice()
            }
        }
        browserProblem = problem
    }

    // MARK: Changing

    /// Runs a step the person asked for. A failure shows in this sheet in Pebble's or the bridge's words (nothing for a
    /// cancelled Face ID); success may leave Pebble's words in `done`.
    func perform<Value>(_ store: RemoteStore, _ work: () async throws -> Value) async -> Value? {
        do {
            let value = try await work()
            return value
        } catch {
            notice = store.takeNotice()
            return nil
        }
    }

    func show(goal record: GoalRecord) {
        goal = record.isCurrent ? record : nil
        if let index = goals.firstIndex(where: { $0.id == record.id }) {
            goals[index].state = record.state
            goals[index].revision = record.revision
            goals[index].progress = record.progress
        }
    }

    func show(context use: ContextUse?) {
        if let use { context = use }
    }

    func show(chrome status: ChromeStatus?) {
        chrome = status
    }

    func show(pebbleBrowser status: PebbleBrowserStatus, tabs: [BrowserTab]) {
        pebbleBrowser = status
        pebbleTabs = tabs
    }

    func forgetRewind() {
        rewind = nil
    }
}

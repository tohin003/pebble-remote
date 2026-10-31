import Foundation
import PebbleProtocol

// Lane Y (fix 8, 2026-10-31): the conversation's Details screen, the phone's copy of Pebble's details drawer
// (src/App.vue TAB_LABELS, MORE_LABELS and the drawer's empty state; src/components/DetailsDrawer.vue,
// ThinkingDisclosure.vue and src/activity.ts for the steps). Pebble's own words are kept word for word and named
// `…Pebble` where the phone changes only a place; the phone's own sentences say what the phone shows and nothing more.
extension AppCopy {
    nonisolated public enum Details {
        // MARK: The screen

        /// The screen's title and the ⋯ menu's item (Pebble's drawer: "Details", DetailsDrawer.vue).
        public static let title = "Details"
        /// The segmented control's name for VoiceOver (DetailsDrawer.vue `aria-label="Details sections"`).
        public static let sections = "Details sections"
        /// The menu of the tabs that have nothing yet (DetailsDrawer.vue "More sections").
        public static let moreSections = "More sections"

        /// The tabs, in Pebble's order and words (App.vue `TAB_LABELS`).
        public static let activity = "Activity"
        public static let task = "Task"
        public static let context = "Context"
        public static let changes = "Changes"
        public static let tools = "Tools"
        public static let browser = "Browser"

        /// The names "More sections" gives the tabs it lists (App.vue `MORE_LABELS`).
        public static let moreTask = "Goal, plan and agents"
        public static let moreContext = "Context"
        public static let moreChanges = "Changes and Git"
        public static let moreTools = "Tools: schedules and shared windows"
        public static let moreBrowser = "Browser and Pebble for Chrome"

        /// The drawer's empty state, word for word (App.vue `#empty`).
        public static let emptyTitle = "Nothing to review yet."
        public static let emptyNote = "Steps, reviews and changes appear here once Pebble works on something."

        /// Activity's badge, read out (DetailsDrawer.vue: ", N waiting").
        public static func waiting(_ count: Int) -> String { "\(count) waiting" }

        /// A tab's read failed: Pebble's or the bridge's words go under it.
        public static let couldNotRead = "Pebble couldn't show this part."
        /// Pull to refresh's words for VoiceOver, and the toolbar's Refresh where Pebble has one.
        public static let refresh = "Refresh"

        // MARK: Activity: what Pebble did, step by step

        /// The step list's heading (App.vue "Steps").
        public static let steps = "Steps"
        /// The list's name while the run works and after (ThinkingDisclosure.vue's `aria-label`).
        public static let doing = "What Pebble is doing"
        public static let did = RunCopy.whatPebbleDid
        /// A step's state, as Pebble's step mark reads it (ThinkingDisclosure.vue `mark`).
        public static let stepDone = "Done"
        public static let stepFailed = "Failed"
        public static let stepInProgress = "In progress"
        public static let stepUnfinished = "Unfinished"
        /// A step's own words (ThinkingDisclosure.vue's disclosure "Details").
        public static let stepDetails = "Details"
        public static let showMore = "Show More"
        public static let showLess = "Show Less"

        /// When a step happened, from the run's start (activity.ts `formatOffset`): "+3.2 s", "+1 min 05 s".
        public static func offset(_ seconds: Double) -> String? {
            guard seconds.isFinite, seconds >= 0 else { return nil }
            if seconds < 60 {
                // JS `toFixed(1)`: tenths, halves away from zero, always one decimal.
                let tenths = Int((seconds * 10).rounded(.toNearestOrAwayFromZero))
                return "+\(tenths / 10).\(tenths % 10) s"
            }
            return RunCopy.formatDuration(seconds).map { "+" + $0 }
        }

        /// What a step took, after its name (ThinkingDisclosure.vue: " · 12 s", only from a second up).
        public static func took(_ seconds: Double?) -> String? {
            guard let seconds, seconds >= 1 else { return nil }
            return RunCopy.formatDuration(seconds)
        }

        /// A step's name with what it took: "Reading README.md · 3 s".
        public static func stepName(_ label: String, took seconds: Double?) -> String {
            took(seconds).map { "\(label) \u{00B7} \($0)" } ?? label
        }

        /// Two or more finished reads and searches in a row, folded (activity.ts `groupRows`): "Explored · read 3
        /// files, 2 searches".
        public static func explored(reads: Int, searches: Int) -> String {
            let words = [
                reads > 0 ? "read \(reads) \(reads == 1 ? "file" : "files")" : "",
                searches > 0 ? "\(searches) \(searches == 1 ? "search" : "searches")" : "",
            ]
            return "Explored \u{00B7} " + words.filter { !$0.isEmpty }.joined(separator: ", ")
        }

        /// A model turn's finished plumbing, folded under its reply (activity.ts `groupRows`): "GPT-5.1 responded · 3
        /// steps", or "Model turn · 3 steps" when no reply row names it.
        public static func modelTurn(_ reply: String?, count: Int) -> String {
            "\(reply ?? "Model turn") \u{00B7} \(count) steps"
        }

        /// The Mac keeps the newest rows of a long task (ThinkingDisclosure.vue): "2 earlier steps are not shown.".
        public static func earlierNotShown(_ count: Int) -> String {
            "\(count) earlier \(count == 1 ? "step is" : "steps are") not shown."
        }

        /// U-45: Pebble's own count of the run's steps is larger than what the phone received. Says both numbers, so
        /// the count above the list always equals the list.
        public static func countedMore(pebble: Int, listed: Int) -> String {
            let counted = "Pebble counted \(pebble) \(pebble == 1 ? "step" : "steps")"
            switch listed {
            case 0: return "\(counted); none of them reached this iPhone."
            case 1: return "\(counted); 1 is listed here."
            default: return "\(counted); \(listed) are listed here."
            }
        }

        /// The line above the steps while the task works (U-58): Pebble's status word, the time since the run started
        /// as the run bar counts it, and the steps listed so far ("Working · 1 min 25 s · 5 steps so far").
        public static func liveLine(word: String, elapsed: String?, steps: Int) -> String {
            var parts = [word]
            if let elapsed { parts.append(elapsed) }
            if steps > 0 { parts.append(steps == 1 ? "1 step so far" : "\(steps) steps so far") }
            return parts.joined(separator: " \u{00B7} ")
        }

        /// The phone stopped reading a very long task's steps before the end, and Pebble gave no count to compare.
        public static let moreThanListed = "This task has more steps than this iPhone lists."

        /// The steps list's empty notes, word for word (ThinkingDisclosure.vue).
        public static let noStepYet = "Pebble hasn't reported a step yet."
        public static let noStepDetails = "No step details were recorded for this reply."
        /// The reasoning summary's heading, word for word (ThinkingDisclosure.vue).
        public static let reasoning = "Pebble's reasoning, summarised by the model"
    }
}

// MARK: - Context (ContextPanel.vue and the composer's ring, App.vue; word for word unless marked)

nonisolated extension AppCopy.Details {
    /// The ring's words (App.vue): "62% of context used".
    public static func contextUsed(_ percent: Int) -> String { "\(percent)% of context used" }
    /// The section's name (RunPanel.vue's toggle "Context use").
    public static let contextUse = "Context use"
    public static let contextNote =
        "Counted by Pebble from its own records: names and counts only, never message text. Nothing here asks the model."
    /// Which request the numbers describe (ContextPanel.vue `basis`).
    public static func contextBasis(_ basis: String, live: Bool) -> String {
        if live { return "The request being answered now." }
        switch basis {
        case "last_request": return "The last request this task sent to the model."
        case "checkpoint": return "The stored window the next request starts from; the model has not seen it in this form yet."
        case "none": return "This task has not sent a request yet."
        default: return "Unknown basis."
        }
    }
    /// "120,400 of 272,000 tokens · 151,600 free" (ContextPanel.vue's summary; numbers as the Mac groups them).
    public static func contextSummary(used: Int, window: Int?, free: Int?, over: Int?) -> String {
        guard let window else { return "\(grouped(used)) tokens; the window is not known." }
        let head = "\(grouped(used)) of \(grouped(window)) tokens"
        if let over, over > 0 { return "\(head) \u{00B7} \(grouped(over)) over the window" }
        return "\(head) \u{00B7} \(grouped(free ?? max(0, window - used))) free"
    }
    /// The categories' names (ContextPanel.vue).
    public static func contextCategory(_ id: String) -> String {
        switch id {
        case "system": "System prompt"
        case "tool_schemas": "Tool descriptions"
        case "memory": "Memory recall"
        case "project_host": "Project and Pebble messages"
        case "conversation": "Conversation"
        case "tool_results": "Tool results"
        case "framing": "Estimate margin and framing"
        default: "Other"
        }
    }
    public static let byCategory = "By category (tokens)"
    public static func tokens(_ count: Int) -> String { "\(grouped(count)) tokens" }

    /// "Compact…" and its confirmation (ContextPanel.vue).
    public static let compact = "Compact…"
    public static let compactTitle = "Compact this task's window?"
    public static let compactMessage =
        "Pebble moves older tool results and turns into this task's archive (still readable there) and keeps your exact instructions, the plan, its evidence and the latest step. Nothing runs, no tool is repeated and memory is unchanged. The task continues from the compacted window when you resume it."
    public static let compactNow = "Compact now"
    public static let compacting = "Compacting…"
    /// Why "Compact…" can't run now (ContextPanel.vue).
    public static func compactUnavailable(_ reason: String?) -> String {
        switch reason {
        case "live": "Compact between turns: pause the task or wait for it to finish."
        case "finished": compactFinished
        case "not_latest": "Only the conversation's latest task can be compacted."
        case "not_resumable": "Reconcile this task's uncertain step first."
        case "between_tools": "This task stopped between tool steps. Resume it to a model boundary before compacting."
        case "no_window": "This task has no stored window yet."
        default: "Compaction is not available for this task now."
        }
    }
    static let compactFinished =
        "This task is finished, so its window is not used again. Your next message starts a new window; Pebble retires older turns there automatically when it fills, and keeps your exact earlier instructions."
    /// What compacting did. Pebble's notice, without the record's number it ends with on the Mac.
    public static func compacted(status: String, messages: Int, toolResults: Int, freed: Int?) -> String {
        switch status {
        case "compacted":
            "Archived \(messages) messages (\(toolResults) tool results) and freed \(grouped(freed ?? 0)) tokens. Your exact instructions, the plan and the latest step were kept."
        case "already_fits": "Nothing was retired: what is left is protected (your instructions, the plan, the latest step)."
        case "fresh_window": compactFinished
        default: "Pebble did not report the outcome; refresh to check."
        }
    }

    /// Numbers as the Mac shows them (`toLocaleString()`).
    public static func grouped(_ number: Int) -> String { number.formatted(.number) }
}

// MARK: - Changes: rewinding files (RewindPanel.vue, App.vue; word for word unless marked)

nonisolated extension AppCopy.Details {
    public static let filesFromLatestTask = "Files from the latest task"
    public static let rewindFiles = "Rewind files"
    public static let rewindIntro =
        "Pebble puts back the files this task wrote, as they were after the step you choose. Each file is an ordinary reviewed edit and is read back afterwards. Commands, connector messages, Git changes and other actions are listed below; they are never undone or run again. A file changed since this task is left alone, and a rewind never deletes a file."
    public static let rewindTo = "Rewind to"
    public static func rewindPoint(_ step: Int) -> String { step == 0 ? "Before this task" : "After step \(step)" }
    public static let rewindChecking = "Checking what a rewind would change…"
    public static let rewindReview = "Review the changes, then rewind."
    public static let rewindNothing = "Nothing to restore for this step."
    public static let rewinding = "Rewinding…"
    public static func restored(_ count: Int) -> String { count == 1 ? "Restored 1 file." : "Restored \(count) files." }
    public static let undoesLastRewind = "This undoes the last rewind."
    public static let files = "Files"
    public static let noFiles = "This task wrote no file after that step."
    /// A file's badge (RewindPanel.vue).
    public static func fileStatus(_ status: String) -> String {
        switch status {
        case "revert": "Will be restored"
        case "unchanged": "Already as it was"
        case "kept": "Kept, never deleted"
        default: "Left alone"
        }
    }
    public static func undoesSteps(_ steps: [Int]) -> String? {
        guard !steps.isEmpty else { return nil }
        return (steps.count == 1 ? "Undoes step " : "Undoes steps ") + steps.map(String.init).joined(separator: ", ")
    }
    public static let diffCut = "The change is longer than shown here."
    /// The phone shows a file's change behind a disclosure.
    public static let showChange = "Show the Change"
    public static let notReverted = "Not reverted"
    public static let noEffects = "No command, connector or other action after that step."
    public static func effectKind(_ kind: String) -> String {
        switch kind {
        case "command": "Command"
        case "connector": "Connector"
        case "git": "Git"
        case "app": "App or screen"
        case "agent": "Delegated agent"
        case "view": "View"
        case "companion": "Companion"
        default: "Action"
        }
    }
    public static func effectStep(_ step: Int?) -> String { step.map { "Step \($0)" } ?? "Step unknown" }
    public static func moreEffects(_ count: Int) -> String { "And \(count) more, also not reverted." }
    public static func rewindButton(_ files: Int) -> String { files == 1 ? "Rewind 1 file" : "Rewind \(files) files" }
    public static let reviewUndoRewind = "Review undoing the last rewind"
    public static let reviewAgain = "Review again"
    public static let rewindNotReady = "Pebble could not prepare this rewind. Nothing was changed."
    /// What a rewind did to each file (RewindPanel.vue's result list).
    public static func rewindResult(path: String, status: String, detail: String?) -> String {
        let word =
            switch status {
            case "reverted": "restored and read back"
            case "refused": "left alone"
            case "kept": "kept"
            case "unchanged": "already as it was"
            case "diverged": "written, but it read back differently"
            default: "not confirmed"
            }
        return "\(path): \(word)" + (detail.map { ". \($0)" } ?? "")
    }
    /// The phone asks before it rewinds (the brief: a plain confirmation, then Face ID). Pebble's own words for what a
    /// rewind does and doesn't do.
    public static func rewindConfirmTitle(_ files: Int) -> String { files == 1 ? "Rewind 1 file?" : "Rewind \(files) files?" }
    public static func rewindConfirmMessage(step: Int) -> String {
        let point = step == 0 ? "before this task" : "after step \(step)"
        return "Pebble puts them back as they were \(point). Commands, connector messages, Git changes and other actions are never undone, and a rewind never deletes a file."
    }
    /// The project's recipes, Git changes, worktrees and environments of Pebble's Changes tab.
    public static let codingWorkflows = "Recipes, Git changes, worktrees and environments"
    public static let onYourMacFootnote =
        "These parts of Pebble's Changes tab are on your Mac for now: open the conversation there to use them."
}

// MARK: - Task: the goal and agents (GoalPanel.vue, AgentPanel.vue, RunPanel.vue; word for word unless marked)

nonisolated extension AppCopy.Details {
    public static let goal = "Goal"
    public static func goalTitle(_ title: String) -> String { "Goal \u{00B7} \(title)" }
    /// "active · 1/3 criteria · 0/2 steps · blocked: needs your review" (GoalPanel.vue).
    public static func goalLine(state: String, met: Int, total: Int, done: Int, steps: Int, blocker: String?) -> String {
        var line = "\(state) \u{00B7} \(met)/\(total) criteria \u{00B7} \(done)/\(steps) steps"
        if let blocker, !blocker.isEmpty { line += " \u{00B7} blocked: \(blocker.lowercased())" }
        return line
    }
    public static let noGoal = "No current goal."
    public static let setGoal = "Set a goal"
    public static let goalPlaceholder = "What should be true when this is done?"
    public static let startGoal = "Start goal"
    public static let goalNote = "Goals are your records: they start no task and grant no permission."
    public static let continueGoal = "Continue goal"
    public static let pauseGoal = "Pause"
    public static let resumeGoal = "Resume"
    public static let markDone = "Mark done"
    public static let abandon = "Abandon…"
    /// The phone's confirmation for Abandon (the Mac turns the button into "Confirm: abandon goal").
    public static let abandonTitle = "Abandon this goal?"
    public static let abandonConfirm = "Confirm: abandon goal"
    public static let keepGoal = "Keep goal"
    /// F5: the phone settles a goal with Face ID, where the criteria show.
    public static let settleNote = "Marking the goal done, abandoning it and settling a criterion ask for Face ID: they are your decisions."
    public static func criteriaCaption(met: Int, total: Int) -> String { "Completion criteria \u{00B7} \(met)/\(total) met" }
    public static let noCriteria = "No accepted criteria yet. A goal is done only when every criterion is met."
    public static func criterionKind(_ kind: String) -> String { kind == "evidence" ? "Task evidence" : "Your check" }
    public static func criterionStatus(_ status: String) -> String {
        switch status {
        case "candidate": "proposed"
        case "unmet": "not met"
        default: status
        }
    }
    public static func checkedBy(_ who: String?) -> String? {
        switch who {
        case "human": "by you"
        case "host": "by task evidence"  // lint-copy: allow (Pebble's field value, never shown)
        default: nil
        }
    }
    public static let proposedAccepted = "Proposed by Pebble, accepted by you"
    public static let markMet = "Mark met"
    public static let markNotMet = "Mark not met"
    /// Pebble's "Verify receipts", in the phone's words (its word for a task record is never shown on screen).
    public static let verifyEvidence = "Verify with task evidence"
    public static let proposals = "Proposed by Pebble \u{00B7} accept or reject"
    public static let accept = "Accept"
    public static let reject = "Reject"
    public static let newCriterion = "New criterion"
    public static let criterionPlaceholder = "e.g. Tests pass on main"
    public static let checkedByTitle = "Checked by"
    public static let addCriterion = "Add criterion"
    public static func stepsCaption(done: Int, total: Int) -> String { "Steps \u{00B7} \(done)/\(total) completed" }
    public static func stepStatus(_ status: String) -> String { status.replacingOccurrences(of: "_", with: " ") }
    public static let blockers = "Blockers"
    public static let earlierGoals = "Earlier goals"
    public static let goalOnMac = "Editing criteria, and adding or blocking steps"
    public static let goalOnMacFootnote = "Pebble's goal panel on your Mac edits criteria and steps."
    /// Pebble's notices after each change (GoalPanel.vue).
    public static let goalStarted = "Goal started. Add completion criteria below."
    public static let goalPaused = "Goal paused."
    public static let goalResumed = "Goal resumed."
    public static let goalDone = "Goal marked done."
    public static let goalAbandoned = "Goal abandoned. Its record is kept and closed."
    public static func criterionNotMet(_ id: String) -> String { "Criterion \(id) marked not met." }
    public static func criterionByEvidence(_ id: String) -> String { "Criterion \(id) is met by current task evidence." }
    public static func criterionByYou(_ id: String) -> String { "Criterion \(id) checked by you." }
    public static func proposalDecided(_ id: String, accepted: Bool) -> String {
        "Proposed criterion \(id) \(accepted ? "accepted" : "rejected")."
    }
    public static let criterionAdded = "Criterion added."
    public static let goalContinued = "Started a new task toward this goal."

    public static let plan = "Plan and agents"
    public static let agents = "Agents"
    public static let noAgents = "No agents recorded for this task."
    public static func agentStatus(_ status: String) -> String { status.replacingOccurrences(of: "_", with: " ") }
    /// "1,200 tokens · 42 s": what an agent used (AgentPanel.vue's usage line, without the model calls it counts).
    public static func agentUse(tokens: Int?, seconds: Double?) -> String? {
        let parts = [tokens.map { "\(grouped($0)) tokens" }, seconds.flatMap(RunCopy.formatDuration)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }
    public static func sendInputTo(_ name: String) -> String { "Send task input to \(name)" }
    public static let agentInput = "Agent task input"
    public static let sendInput = "Send input"
    public static let cancelAgent = "Cancel agent and descendants"
    public static func cancelAgentTitle(_ name: String) -> String { "Cancel \u{201C}\(name)\u{201D}?" }
    public static let cancelAgentMessage = "The agents under it stop too. This can't be undone."
    public static let readOnlyAgent = "This agent\u{2019}s saved record is read only."
    public static let inputSent = "Input sent."
    public static let cancelRequested = "Cancellation requested."
    public static let result = "Result"
}

// MARK: - Tools (CompanionWorkflows.vue, ScreenSessions.vue, App.vue; word for word unless marked)

nonisolated extension AppCopy.Details {
    public static let schedules = "Schedules"
    public static let schedulesNote =
        "Schedules in this chat fire only while the Pebble service is running. Permissions still apply on each run; nothing is approved in advance. Pausing or deleting a schedule never cancels an unrelated run. After sleep, a schedule runs once at its latest missed time unless it skips late times."
    public static let noSchedules = "No schedules in this chat."
    public static let scheduleNotices = "Scheduled task notifications"
    public static let noWindows = "Pebble isn't using any window in this conversation."
    public static let windowsNote =
        "You choose each window or tab Pebble may use; it stays allowed in this conversation for up to 15 minutes, and a message in another conversation ends it. Window text is shown as the app or page wrote it; it never gives Pebble permission. At a sign-in, a code or a check, Pebble stops and it's your turn: you finish it yourself, and Pebble never sees what you type."
    /// A shared window's state (ScreenSessions.vue).
    public static func sessionState(_ state: String, pending: Bool) -> String {
        switch state {
        case "active": pending ? "Waiting for your next message here" : "Pebble can use it"
        case "handoff": "Your turn"
        case "interrupted": "Paused: the last step has an uncertain outcome"
        default: state
        }
    }
    public static let sessionDone = "Done"
    public static let endAccess = "End access"
    public static func sessionDoneNotice(tab: Bool) -> String {
        "Done. Pebble looks at the \(tab ? "tab" : "window") again before it does anything else."
    }
    public static func accessEnded(tab: Bool) -> String { "Access ended. Pebble can no longer use this \(tab ? "tab" : "window")." }
    /// IA rule 4: the same lists across conversations live in Settings; this says so where they meet.
    public static let toolsAlsoInSettings = "Every conversation's schedules and shared windows are also in Settings › Across Conversations."
}

// MARK: - Browser (PebbleBrowser.vue; word for word unless marked)

nonisolated extension AppCopy.Details {
    public static let yourChrome = "Your Chrome"
    /// The status pill (PebbleBrowser.vue), first match wins.
    public static func chromeState(
        connected: Bool, paused: Bool, pairing: Bool, locked: Bool, present: Bool, helper: Bool
    ) -> String {
        if connected { return paused ? "Paused" : "Connected" }
        if pairing { return "Pairing" }
        if locked { return "Pairing paused" }
        if present { return "Not paired" }
        if helper { return "Not connected" }
        return "Not set up"
    }
    public static let chromeChecking = "Checking…"
    public static let chromeNote =
        "Pebble works only in tabs you share from Chrome's toolbar, only on the site you shared, and only for a task you choose here. Sign-in and payment pages are always your turn, and anything that sends, buys, posts or deletes waits for your approval."
    public static func chromeVersions(chrome: String, extension version: String?) -> String {
        "Chrome \(chrome) \u{00B7} Pebble for Chrome \(version ?? "unknown version")"
    }
    public static let chromePausedLine = "Paused. Pebble doesn't read or act in your Chrome tabs until you resume."
    /// Pebble shows the pairing code in its own window only; the phone says where it is.
    public static let pairingOnMac = "A pairing code is waiting in Pebble on your Mac. Type it in the Pebble for Chrome popup."
    public static let noSharedTab =
        "No tab is shared. In Chrome, click the Pebble button on a tab and choose \u{201C}Let Pebble use this tab\u{201D}."
    public static let noTitle = "No title"
    public static let titleNote = "Page title, written by the page"
    public static func tabScope(_ scope: String) -> String { scope == "site" ? "Kept for this site" : "Just this visit" }
    public static func sharedTabState(_ state: String, acting: Bool, granted: Bool) -> String {
        switch state {
        case "away": "Paused: the tab is on another site"
        case "handback": "Your turn: a sign-in or payment page"
        default: acting ? "Pebble is working here" : granted ? "A task can use it" : "Ready"
        }
    }
    public static let pause = "Pause"
    public static let resume = "Resume"
    public static let stopInChrome = "Stop Pebble in Chrome"
    public static let letPebbleUseTab = "Let Pebble use this tab…"
    public static let pausedNotice = "Paused. Pebble doesn't read or act in your Chrome tabs until you resume."
    public static let resumedNotice = "Resumed. Pebble looks at each tab again before it does anything."
    public static func stoppedNotice(_ tabs: Int) -> String {
        "Stopped. "
            + (tabs == 0 ? "No Chrome tab was shared." : tabs == 1 ? "Pebble let go of 1 shared tab in Chrome." : "Pebble let go of \(tabs) shared tabs in Chrome.")
    }
    /// Pebble's Mac calls it "Pebble's browser", a name its own jargon rule retires elsewhere; the phone says "own".
    public static let pebbleBrowser = "Pebble's own browser"
    public static let pebbleBrowserNote =
        "A separate browser with its own private profile, started and stopped only here. Pebble uses a tab only when you grant it, only on the sites you tick, for the current task. Sign-in, codes and CAPTCHAs are always your turn. Your own browser and its sign-ins are not touched."
    public static func pebbleBrowserState(running: Bool, product: String?) -> String {
        running ? "Running" + (product.map { " \u{00B7} \($0)" } ?? "") : "Not running"
    }
    public static let startBrowser = "Start Pebble's own browser"
    public static let stopBrowser = "Stop Pebble's own browser"
    public static let checkAgain = "Check again"
    public static let noTabs = "No tabs are open."
    public static func site(_ origin: String?) -> String { "Site: \(origin ?? "not a website, so it cannot be granted")" }
    public static let browserNotAvailable = "Pebble's own browser is not available yet."
    public static let browserStarted = "Pebble's own browser is running with its private profile."
    public static let browserStopped = "Pebble's own browser stopped."
    /// What stays on the Mac (excluded from the phone: installing Chrome's helper, pairing, forgetting the profile).
    public static let chromeSetup = "Connect Chrome and pair Pebble for Chrome"
    public static let forgetProfile = "Forget browser profile"
    public static let browserOnMacFootnote = "Setting up Chrome, pairing and forgetting the browser's profile happen in Pebble on your Mac."

    // The grant (PebbleBrowser.vue's grant card)
    public static func grantTitle(chrome: Bool) -> String { chrome ? "Let Pebble use this Chrome tab" : "Let Pebble use this tab" }
    public static func grantChromeNote(_ origin: String) -> String {
        "The title is page text; it can't give Pebble permission. Pebble can use this tab only on \(origin), the site you shared. If the tab goes to another site, shows a sign-in or payment page, or you stop sharing in Chrome, Pebble stops and it's your turn."
    }
    public static let grantPebbleNote =
        "The title is page text; it can't give Pebble permission. If the tab goes to a site you didn't tick, or shows a sign-in, a code or a CAPTCHA, Pebble stops and it's your turn."
    public static let grantWhen = "With a task running here, it can use the tab now; otherwise your next message in this conversation can."
    public static let grantSites = "Sites Pebble may use in this tab"
    public static let grantWhat = "What Pebble may do"
    public static let lookAround = "Look around"
    public static let lookAroundNote = "Move focus, scroll, and open or close sections. Nothing changes."
    public static let fillIn = "Fill in"
    public static let fillInNote = "Choose options, tick boxes and type text, never into a password, code or card field."
    public static let pressButtons = "Press buttons"
    public static let pressButtonsNote =
        "Every press waits for your approval in Pebble first, because pages decide what a button does."
    public static let screenshots = "Screenshots"
    public static let screenshotsToggle = "Let Pebble see screenshots of this tab"
    public static let screenshotsNote =
        "Only models that can see images get them. A screenshot shows everything visible on the page, including anything private; Pebble still reads the page as text either way. Screenshots go to the model and are not kept."
    public static let forHowLong = "For how long"
    public static func minutes(_ count: Int) -> String { "\(count) minutes" }
    public static let grantThisTab = "Grant this tab"
    public static let turnOnScreenAndGrant = "Turn on Screen control and grant"
    /// The success notice (PebbleBrowser.vue), on the phone's sheet.
    public static func granted(chrome: Bool, sites: [String], pending: Bool, minutes: Int, screenshots: Bool) -> String {
        var text =
            "Pebble can use this \(chrome ? "Chrome tab" : "tab") on \(sites.joined(separator: ", ")) "
            + (pending ? "from your next message in this conversation" : "for the current task") + ", for \(minutes) minutes."
        if screenshots { text += " It may also see screenshots of the tab; they go to the model and are not kept." }
        return text + " End access on its row here at any time."
    }
}

// MARK: - Settings › Across Conversations: each row opens its conversation's Details › Tools (the lead, 02:30)

nonisolated extension AppCopy.Details {
    /// The Settings section's footer.
    public static let acrossSectionNote =
        "These lists gather every conversation\u{2019}s schedules and shared windows. Each opens its conversation\u{2019}s Details \u{203A} Tools, where its controls are."
    /// The lists' footer.
    public static let acrossListNote = "Tap one to open its conversation\u{2019}s Details \u{203A} Tools, where its controls are."
    /// VoiceOver's hint on such a row.
    public static let opensTools = "Opens its conversation\u{2019}s Details on Tools"
}

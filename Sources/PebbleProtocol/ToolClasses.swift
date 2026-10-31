import Foundation

// Pebble's tool classes and run-state groups, ported from the Pebble checkout (read-only):
// - backend/pebble/activity_kinds.py `_CLASSES`, `classify()` and `HOST` (src/statusWords.ts TOOL_CLASS_TABLE and
//   RUN_STATUS are the desktop's copies; Pebble's test_activity_kinds.py keeps those equal);
// - backend/pebble/runtime.py `LIVE` and `RESUMABLE`; backend/pebble/app.py `SIMPLE_CARDS` and `stop()`.
// A status word is never built from a progress label: only from these keys.

extension StatusKey {
    /// Which status each of Pebble's tools shows while it runs, in Pebble's order (activity_kinds._CLASSES).
    public static let toolClasses: [(key: StatusKey, tools: [String])] = [
        (
            .reading,
            [
                "Read", "ReadAttachment", "ReadURL", "ReadSource", "ReadProcess", "ReadRunEvidence", "LoadSkill",
                "LoadPluginTool", "LoadPluginData", "ReadPluginData", "ReadPluginMedia", "ReadGitStatus", "ReadGitDiff",
                "ReadGitHistory", "ReadGitPlanReceipt", "ReadGitWorktrees", "ReadWorktreeExport", "ListProjectRecipes",
                "ScreenObserve", "ResearchStatus", "ReadFile", "Screenshot",
            ]
        ),
        (
            .searching,
            [
                "Glob", "Grep", "SearchFiles", "CodeReferences", "WebSearch", "Weather", "SearchPluginTools",
                "SearchPluginData", "ResearchPlan", "FindTool",
            ]
        ),
        (
            .editing,
            [
                "Write", "Append", "Edit", "ProposePatch", "IntegrateAgentPatch", "ProposeGitChange",
                "PreviewWorktreeExport", "IntegrateWorktreeFile", "WriteFile", "EditFile",
            ]
        ),
        (.testing, ["RunTests", "RunRecipe"]),
        (
            .running,
            [
                "RunCommand", "StartCommand", "WaitProcess", "StopProcess", "WriteProcessInput", "RunPlan",
                "StartPreview", "PrepareEnvironment", "RunCode", "Shell",
            ]
        ),
        (
            .delegating,
            [
                "SpawnAgent", "SpawnWorktreeAgent", "ReadAgentTree", "SendAgentMessage", "WaitForAgents",
                "DelegateAgentTask", "StopAgent", "RetryAgent", "AskParentQuestion", "AnswerAgentQuestion",
                "PromoteAgentQuestion", "ReviewAgentResult", "ReadAgentMessage", "ReadAgentPatch", "RequestAgentEffect",
                "ReadAgentEffect", "ReadAgentEffects", "ExecuteAgentEffect", "DismissAgentEffect",
            ]
        ),
        (.viewing, ["UIRender", "UIUpdate", "RenderMod"]),
        (.thinking, ["AskUserQuestion", "UpdatePlan", "UpdateGoal", "MemoryPropose"]),
        (
            .working,
            ["OpenApp", "PluginCall", "FetchPluginData", "ScreenAct", "ScreenRequest", "OpenURL", "AppAction", "BrowserRequest"]
        ),
    ]

    private static let toolClassByName: [String: StatusKey] = Dictionary(
        toolClasses.flatMap { entry in entry.tools.map { ($0, entry.key) } }, uniquingKeysWith: { first, _ in first })

    /// The class a tool shows (statusWords.ts `toolClass`): anything unknown, or a name a model invented, is plain
    /// `working`, so a tool called "Approve" cannot borrow a meaning. Used only when a progress event carries no
    /// `activity` field (Pebble before Phase 19).
    public static func forTool(_ tool: String?) -> StatusKey {
        guard let tool, let key = toolClassByName[tool] else { return .working }
        return key
    }

    /// activity_kinds.classify(tool, kind): the activity key of one progress event, or nil when the event is not an
    /// activity. Only kind "working" describes what Pebble is doing now; one without a tool is the model's own turn.
    public static func classify(tool: String?, kind: String?) -> StatusKey? {
        guard kind == "working" else { return nil }
        guard let tool, !tool.isEmpty else { return .thinking }
        return forTool(tool)
    }

    /// The keys a progress event's tool may show (companionState.ts CLASS_POSES): the eight tool classes.
    public var isToolClass: Bool {
        switch self {
        case .reading, .searching, .editing, .testing, .running, .delegating, .viewing, .working: true
        default: false
        }
    }
}

extension RunState {
    /// A worker is on it (runtime.LIVE): queued, running, retry_wait.
    public var isLive: Bool { [.queued, .running, .retryWait].contains(self) }

    /// Held for the person, and Stop can end it (app.py `stop()`): waiting for an approval or an answer, or paused.
    public var isWaitingForPerson: Bool { [.waitingApproval, .waitingInput, .paused].contains(self) }

    /// Pebble's own states (runtime.STATES); anything else came from a newer Pebble.
    public static let pebbleStates: Set<RunState> = [
        .queued, .running, .retryWait, .paused, .interrupted, .stopped, .failed, .budgetExhausted, .waitingApproval,
        .waitingInput, .verificationRequired, .completed, .needsReconciliation,
    ]
}

extension CardKind {
    /// The cards the companion may answer (app.py SIMPLE_CARDS, Pebble's D133): a site, a window, bringing a window
    /// forward. `approve_simple` and `reject_simple` accept only these.
    public static let simpleKinds: Set<CardKind> = [.browserGrant, .screenGrant, .screenRaise]

    public var isSimple: Bool { Self.simpleKinds.contains(self) }
}

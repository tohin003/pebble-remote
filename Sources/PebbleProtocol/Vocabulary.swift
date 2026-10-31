import Foundation

// Pebble's own vocabulary, mirrored from the desktop app so the phone says exactly what Pebble says.
// Sources (read-only): src/statusWords.ts, src/permissionModes.ts, backend/pebble/activity_kinds.py in the Pebble
// checkout. Unknown values from a newer Pebble are kept as they are, never an error.

/// What Pebble is doing right now. The words for each key live in PebbleDesign (StatusCopy); the keys are Pebble's.
public enum StatusKey: String, Sendable, Hashable, CaseIterable, Codable {
    // While a run is live (statusWords.ts ACTIVITY_KEYS)
    case thinking, writing, reading, searching, editing, testing, running, delegating, viewing, working, loading
    // Set by Pebble's state (statusWords.ts HOST_KEYS)
    case question, review, reconnecting, blocked, uncertain, offline, paused, error, sending

    public var isLive: Bool {
        switch self {
        case .thinking, .writing, .reading, .searching, .editing, .testing, .running, .delegating, .viewing, .working,
            .loading:
            true
        default:
            false
        }
    }
}

/// A run's state as Pebble's run ledger reports it. Tolerant: any string is kept.
public struct RunState: RawRepresentable, Sendable, Hashable, Codable, CustomStringConvertible {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let queued = RunState(rawValue: "queued")
    public static let running = RunState(rawValue: "running")
    public static let waitingApproval = RunState(rawValue: "waiting_approval")
    public static let waitingInput = RunState(rawValue: "waiting_input")
    public static let retryWait = RunState(rawValue: "retry_wait")
    public static let paused = RunState(rawValue: "paused")
    public static let budgetExhausted = RunState(rawValue: "budget_exhausted")
    public static let verificationRequired = RunState(rawValue: "verification_required")
    public static let needsReconciliation = RunState(rawValue: "needs_reconciliation")
    public static let completed = RunState(rawValue: "completed")
    public static let failed = RunState(rawValue: "failed")
    public static let stopped = RunState(rawValue: "stopped")
    public static let cancelled = RunState(rawValue: "cancelled")
    public static let interrupted = RunState(rawValue: "interrupted")

    /// The host key a waiting or stuck state shows (statusWords.ts RUN_STATUS); nil while working or when settled.
    public var statusKey: StatusKey? {
        switch self {
        case .retryWait: .reconnecting
        case .waitingInput: .question
        case .waitingApproval: .review
        case .budgetExhausted, .verificationRequired: .blocked
        case .needsReconciliation: .uncertain
        case .paused: .paused
        case .failed: .error
        default: nil
        }
    }

    /// Finished one way or another: nothing more will happen without the person.
    public var isSettled: Bool {
        [.completed, .failed, .stopped, .cancelled, .interrupted].contains(self)
    }
}

/// The permission modes (permissionModes.ts). The exact copy for each lives in PebbleDesign (ModeCopy).
public enum PermissionMode: String, Sendable, Hashable, CaseIterable, Codable {
    case ask, auto, full
}

/// Which requests ask for the faster model tier (Pebble 1.9.26+, settings key `fast_replies`).
public enum FastReplies: String, Sendable, Hashable, CaseIterable, Codable {
    case off
    case followUps = "follow_ups"
    case longTasks = "long_tasks"
    case always
}

/// The kinds of card Pebble asks the person to review (src/types.ts Action.kind). Unknown kinds are kept.
public struct CardKind: RawRepresentable, Sendable, Hashable, Codable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let edit = CardKind(rawValue: "edit")
    public static let tests = CardKind(rawValue: "tests")
    public static let app = CardKind(rawValue: "app")
    public static let command = CardKind(rawValue: "command")
    public static let plugin = CardKind(rawValue: "plugin")
    public static let git = CardKind(rawValue: "git")
    public static let worktree = CardKind(rawValue: "worktree")
    public static let install = CardKind(rawValue: "install")
    public static let shell = CardKind(rawValue: "shell")
    public static let file = CardKind(rawValue: "file")
    public static let screen = CardKind(rawValue: "screen")
    public static let screenGrant = CardKind(rawValue: "screen_grant")
    public static let url = CardKind(rawValue: "url")
    public static let screenRaise = CardKind(rawValue: "screen_raise")
    public static let appAction = CardKind(rawValue: "app_action")
    public static let browserGrant = CardKind(rawValue: "browser_grant")
}

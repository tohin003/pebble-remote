import Foundation

/// A run's plan from UpdatePlan: the header's `plan` and the `plan` event's `steps` (workView.ts `parsePlan`). Step
/// titles are the model's words, shown literally. At most 20 steps; `done` and `total` are counted from the steps kept,
/// so the ring and the rail always agree.
public struct WorkPlan: Sendable, Hashable {
    public enum Status: String, Sendable, Hashable, CaseIterable {
        case pending
        case inProgress = "in_progress"
        case blocked
        case completed
    }
    public struct Step: Sendable, Hashable {
        /// Nil when the model gave none (the screen says "Step").
        public var title: String?
        public var status: Status
    }

    public var steps: [Step]
    public var done: Int { steps.filter { $0.status == .completed }.count }
    public var total: Int { steps.count }

    /// From `{steps: [{title, status}]}`; nil without a step whose status is one of the four.
    public init?(json: JSONValue?) {
        guard let list = json?["steps"]?.array else { return nil }
        let steps: [Step] = list.compactMap { value -> Step? in
            guard let fields = ViewFields(value), let status: Status = fields.word("status") else { return nil }
            return Step(title: fields.text("title", 120), status: status)
        }
        guard !steps.isEmpty else { return nil }
        self.steps = Array(steps.prefix(20))
    }

    /// The step under way, if any.
    public var current: Step? { steps.first { $0.status == .inProgress } }
}

/// The reply's header (`run_activity`'s `header`): the plan's progress, the run's state and the time. The task line is
/// not in it: it is the first line of the person's own message, which the phone already holds.
public struct WorkHeader: Sendable, Hashable {
    public var plan: WorkPlan?
    /// The run's state (Pebble's run states: running, completed, waiting_approval …).
    public var state: String?
    /// Seconds Pebble counted.
    public var elapsed: Double?

    public init(plan: WorkPlan? = nil, state: String? = nil, elapsed: Double? = nil) {
        self.plan = plan
        self.state = state
        self.elapsed = elapsed
    }

    /// Nil when `json` is not an object. Unknown parts are null in the header, and stay nil here.
    public init?(json: JSONValue?) {
        guard let fields = ViewFields(json) else { return nil }
        self.init(plan: WorkPlan(json: fields.object["plan"]), state: fields.text("state", 32), elapsed: fields.amount("elapsed"))
    }
}

/// The receipt of a settled run (`run_activity`'s `summary`, null until it settles and while it waits for the person).
/// Pebble records no price, so its cost is the tokens.
public struct WorkSummary: Sendable, Hashable {
    public struct Files: Sendable, Hashable {
        public var count: Int
        public var added: Int
        public var removed: Int
    }
    public struct Commands: Sendable, Hashable {
        public var count: Int
        public var failed: Int
    }
    public struct Tests: Sendable, Hashable {
        public var passed: Int
        public var failed: Int
    }
    public struct Tokens: Sendable, Hashable {
        public var input: Int
        public var cached: Int
        public var output: Int
    }

    /// Applied edits.
    public var files: Files?
    public var commands: Commands?
    /// From the last test run.
    public var tests: Tests?
    /// The last check's verdict.
    public var checks: String?
    public var seconds: Double?
    public var tokens: Tokens?

    public init?(json: JSONValue?) {
        guard let fields = ViewFields(json) else { return nil }
        if let files = fields.nested("files"), let count = files.count("count") {
            self.files = Files(count: count, added: files.count("added") ?? 0, removed: files.count("removed") ?? 0)
        }
        if let commands = fields.nested("commands"), let count = commands.count("count") {
            self.commands = Commands(count: count, failed: commands.count("failed") ?? 0)
        }
        if let tests = fields.nested("tests"), tests.has("passed") || tests.has("failed") {
            self.tests = Tests(passed: tests.count("passed") ?? 0, failed: tests.count("failed") ?? 0)
        }
        checks = fields.text("checks", 80)
        seconds = fields.amount("seconds")
        if let tokens = fields.nested("tokens") {
            self.tokens = Tokens(
                input: tokens.count("input") ?? 0, cached: tokens.count("cached") ?? 0, output: tokens.count("output") ?? 0)
        }
    }

    /// Nothing worth a line: no files, commands, tests or checks, and no time.
    public var isEmpty: Bool {
        files == nil && commands == nil && tests == nil && checks == nil && (seconds ?? 0) <= 0 && tokens == nil
    }
}

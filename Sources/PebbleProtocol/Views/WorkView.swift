import Foundation

/// One card's data in pebble-ui-spec v1's work view: what Pebble did in one step, built by Pebble from its own records
/// and sent as an activity item's optional `view` (`run_activity` and the `activity` event).
///
/// A view whose `v` is not 1, whose `type` this version does not know, or that is not an object, is nil: its item then
/// shows as its label and detail with "Update the app to see this view" (rule 1). A known type keeps only the fields
/// it knows, each checked and clamped to the spec's bound; a field that fails its check is left out, as Pebble's own
/// windows do (workView.ts `parseView`). Every string is display text: paths, commands, output, branch names, window
/// titles and agent names come from a project, a page, a window or a model and are shown literally (rule 3).
public struct WorkView: Sendable, Hashable {
    public enum Content: Sendable, Hashable {
        case read(Read)
        case search(Search)
        case web(Web)
        case edit(Edit)
        case command(Command)
        case tests(Tests)
        case git(Git)
        case window(Window)
        case agent(Agent)
        case checks(Checks)
        case review(Review)
        case question(Question)
    }

    public var content: Content
    /// The view lost list items from the end to stay under 4 KB.
    public var more: Bool

    /// The only version this app reads.
    public static let version = 1
    /// The types version 1 describes (`x-pebble-view-types`), in the spec's order.
    public static let types = [
        "read", "search", "web", "edit", "command", "tests", "git", "window", "agent", "checks", "review", "question",
    ]

    public init(_ content: Content, more: Bool = false) {
        self.content = content
        self.more = more
    }

    public init?(json: JSONValue?) {
        guard let fields = ViewFields(json), let version = fields.object["v"], ViewFields.wholeNumber(version) == Self.version,
            let type = fields.object["type"]?.string
        else { return nil }
        let content: Content
        switch type {
        case "read": content = .read(Read(fields))
        case "search": content = .search(Search(fields))
        case "web": content = .web(Web(fields))
        case "edit": content = .edit(Edit(fields))
        case "command": content = .command(Command(fields))
        case "tests": content = .tests(Tests(fields))
        case "git": content = .git(Git(fields))
        case "window": content = .window(Window(fields))
        case "agent": content = .agent(Agent(fields))
        case "checks": content = .checks(Checks(fields))
        case "review": content = .review(Review(fields))
        case "question": content = .question(Question(fields))
        default: return nil
        }
        self.init(content, more: fields.flag("more") == true)
    }

    /// The spec's name for the type.
    public var type: String {
        switch content {
        case .read: "read"
        case .search: "search"
        case .web: "web"
        case .edit: "edit"
        case .command: "command"
        case .tests: "tests"
        case .git: "git"
        case .window: "window"
        case .agent: "agent"
        case .checks: "checks"
        case .review: "review"
        case .question: "question"
        }
    }

    /// The step's own state, for the types that carry one.
    public var state: WorkState? {
        switch content {
        case .edit(let view): view.state
        case .command(let view): view.state
        case .tests(let view): view.state
        case .git(let view): view.state
        case .agent(let view): view.state
        case .review(let view): view.state
        case .question(let view): view.state
        case .read, .search, .web, .window, .checks: nil
        }
    }

    /// The card this view joins (workView.ts `KIND`); nil for review and question items, which stay rows because
    /// their real cards are the review cards and questions the conversation already shows.
    public var cardKind: WorkCardKind? {
        switch content {
        case .read, .search: .explored
        case .web: .web
        case .edit: .files
        case .command: .command
        case .tests: .tests
        case .git: .git
        case .window: .window
        case .agent: .agents
        case .checks: .checks
        case .review, .question: nil
        }
    }
}

/// A step's state wherever a view carries one (pebble-ui-spec v1, "The work view's types").
public enum WorkState: String, Sendable, Hashable, CaseIterable {
    /// Waiting for the person.
    case waiting
    case running
    case done
    case failed
    case declined
    /// Pebble's own check held it.
    case held
    case undone
    case stopped

    /// The tone its words take (rule 5): done in green, failed or declined in red, waiting or held in amber.
    public var tone: WorkTone {
        switch self {
        case .done: .good
        case .failed, .declined: .bad
        case .waiting, .held: .open
        case .running, .undone, .stopped: .neutral
        }
    }
}

/// What a colour means beside its words (pebble-ui-spec v1, rule 5).
public enum WorkTone: Sendable, Hashable {
    case good, bad, open, neutral
}

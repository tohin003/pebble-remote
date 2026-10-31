import Foundation

// The work view's types, field by field, with the bounds of pebble-ui-spec v1 (workView.ts `SPEC`). Nil fields were
// absent or failed their check.

extension WorkView {
    /// Pebble read a file. A private file (keys, `.env`) has only `isPrivate`, never its name.
    public struct Read: Sendable, Hashable {
        public var path: String?
        /// The first line read.
        public var start: Int?
        /// Lines in the file.
        public var total: Int?
        public var isPrivate: Bool

        init(_ fields: ViewFields) {
            path = fields.text("path", 200)
            start = fields.count("start")
            total = fields.count("total")
            isPrivate = fields.flag("private") == true
        }
    }

    /// A search of the project.
    public struct Search: Sendable, Hashable {
        public enum Tool: String, Sendable, Hashable {
            case grep = "Grep", glob = "Glob", searchFiles = "SearchFiles", codeReferences = "CodeReferences"
        }
        public var tool: Tool?
        public var query: String?
        public var hits: Int?

        init(_ fields: ViewFields) {
            tool = fields.word("tool")
            query = fields.text("query", 120)
            hits = fields.count("hits")
        }
    }

    /// A web search or page: host names only, never a full address.
    public struct Web: Sendable, Hashable {
        public var query: String?
        public var sites: [String]

        init(_ fields: ViewFields) {
            query = fields.text("query", 120)
            sites = fields.texts("sites", max: 5, limit: 120) ?? []
        }
    }

    /// A file change, counted from its diff.
    public struct Edit: Sendable, Hashable {
        public var path: String?
        public var added: Int?
        public var removed: Int?
        /// The file did not exist.
        public var isNew: Bool
        public var isPrivate: Bool
        public var state: WorkState?
        public var actionID: String?

        init(_ fields: ViewFields) {
            path = fields.text("path", 200)
            added = fields.count("added")
            removed = fields.count("removed")
            isNew = fields.flag("new") == true
            isPrivate = fields.flag("private") == true
            state = fields.word("state")
            actionID = fields.text("action_id", 64)
        }
    }

    /// A terminal command, masked for secrets by Pebble.
    public struct Command: Sendable, Hashable {
        /// The command as the person would read it.
        public var command: String?
        /// "Project folder › scripts".
        public var place: String?
        public var usesNetwork: Bool?
        public var state: WorkState?
        public var exit: Int?
        public var seconds: Double?
        /// Its last lines of output.
        public var tail: [String]
        /// The output was longer than the tail.
        public var isCut: Bool
        public var actionID: String?

        init(_ fields: ViewFields) {
            command = fields.text("command", 400)
            place = fields.text("where", 80)
            usesNetwork = fields.flag("network")
            state = fields.word("state")
            exit = fields.count("exit")
            seconds = fields.amount("seconds")
            tail = fields.texts("tail", max: 8, limit: 160) ?? []
            isCut = fields.flag("cut") == true
            actionID = fields.text("action_id", 64)
        }
    }

    /// A test run.
    public struct Tests: Sendable, Hashable {
        /// python-pytest, npm-test …
        public var recipe: String?
        public var state: WorkState?
        public var passed: Int?
        public var failed: Int?
        public var skipped: Int?
        public var errors: Int?
        public var total: Int?
        /// The failing tests' names, for display only.
        public var failing: [String]
        public var exit: Int?
        public var seconds: Double?
        public var actionID: String?

        init(_ fields: ViewFields) {
            recipe = fields.text("recipe", 40)
            state = fields.word("state")
            passed = fields.count("passed")
            failed = fields.count("failed")
            skipped = fields.count("skipped")
            errors = fields.count("errors")
            total = fields.count("total")
            failing = fields.texts("failing", max: 10, limit: 160) ?? []
            exit = fields.count("exit")
            seconds = fields.amount("seconds")
            actionID = fields.text("action_id", 64)
        }
    }

    /// A Git step or a status read.
    public struct Git: Sendable, Hashable {
        /// commit, merge, push, status …
        public var operation: String?
        /// Pebble's sentence for the plan.
        public var summary: String?
        public var branch: String?
        public var upstream: String?
        public var ahead: Int?
        public var behind: Int?
        public var changed: Int?
        /// A short hash.
        public var commit: String?
        /// The remote's name.
        public var pushTo: String?
        public var isDestructive: Bool
        public var publishes: Bool
        public var state: WorkState?
        public var actionID: String?

        init(_ fields: ViewFields) {
            operation = fields.text("op", 24)
            summary = fields.text("summary", 240)
            branch = fields.text("branch", 120)
            upstream = fields.text("upstream", 120)
            ahead = fields.count("ahead")
            behind = fields.count("behind")
            changed = fields.count("changed")
            commit = fields.text("commit", 12)
            pushTo = fields.text("push_to", 64)
            isDestructive = fields.flag("destructive") == true
            publishes = fields.flag("publication") == true
            state = fields.word("state")
            actionID = fields.text("action_id", 64)
        }
    }
}

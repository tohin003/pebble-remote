import Foundation

extension WorkView {
    /// A look or a press in an app window.
    public struct Window: Sendable, Hashable {
        public enum Verdict: String, Sendable, Hashable {
            case happened
            case nothingChanged = "nothing_changed"
            case uncertain
            case refused
        }
        /// Pebble's newest observation of the window: a reference and its size, never the pixels (no route serves
        /// the picture in version 1).
        public struct Picture: Sendable, Hashable {
            public var width: Int
            public var height: Int
        }
        /// Where it pressed, in the picture's pixels.
        public struct Point: Sendable, Hashable {
            public var x: Double
            public var y: Double
        }

        public var app: String?
        public var title: String?
        /// Pressed, Typed into, Clicked …
        public var verb: String?
        public var target: String?
        /// What changed: before and after.
        public var before: String?
        public var after: String?
        public var verdict: Verdict?
        public var picture: Picture?
        public var point: Point?

        init(_ fields: ViewFields) {
            app = fields.text("app", 64)
            title = fields.text("title", 60)
            verb = fields.text("verb", 40)
            target = fields.text("target", 60)
            before = fields.text("before", 40)
            after = fields.text("after", 40)
            verdict = fields.word("verdict")
            if let picture = fields.nested("picture"), let width = picture.count("width"), let height = picture.count("height"),
                width > 0, height > 0
            {
                self.picture = Picture(width: width, height: height)
            }
            if let point = fields.nested("point"), let x = point.amount("x"), let y = point.amount("y") {
                self.point = Point(x: x, y: y)
            }
        }

        /// The press point inside the picture's frame, when both are known (WorkCard.vue `frame`).
        public var pressInFrame: (picture: Picture, point: Point)? {
            guard let picture, let point else { return nil }
            return (picture, Point(x: min(point.x, Double(picture.width)), y: min(point.y, Double(picture.height))))
        }
    }

    /// A child agent.
    public struct Agent: Sendable, Hashable {
        public var name: String?
        public var state: WorkState?
        public var depth: Int?
        public var parent: String?
        public var seconds: Double?
        public var tokens: Int?

        init(_ fields: ViewFields) {
            name = fields.text("name", 60)
            state = fields.word("state")
            depth = fields.count("depth")
            parent = fields.text("parent", 64)
            seconds = fields.amount("seconds")
            tokens = fields.count("tokens")
        }
    }

    /// The completion check: AgentGuard's requirement ledger in plain words.
    public struct Checks: Sendable, Hashable {
        public struct TestRun: Sendable, Hashable {
            public var runner: String?
            public var passed: Int?
            public var failed: Int?
            /// Run on the current files.
            public var isCurrent: Bool
        }
        public struct Requirement: Sendable, Hashable {
            public enum State: String, Sendable, Hashable { case met, open }
            public var text: String
            /// Met when the check found nothing unmet; otherwise open. Never "unmet" one by one: Pebble's records
            /// keep how many issues were unmet, not which requirement each belongs to.
            public var state: State?
        }

        /// "Verified · pytest 42 passed on current files".
        public var verdict: String?
        public var tests: TestRun?
        public var filesChanged: Int?
        public var issues: Int?
        public var isRepairable: Bool
        public var requirements: [Requirement]
        /// How many issues are not met yet; the reply says which.
        public var unmet: Int?
        /// An earlier check found issues and this one found none.
        public var wasRepaired: Bool

        init(_ fields: ViewFields) {
            verdict = fields.text("verdict", 80)
            if let tests = fields.nested("tests") {
                self.tests = TestRun(
                    runner: tests.text("runner", 40), passed: tests.count("passed"), failed: tests.count("failed"),
                    isCurrent: tests.flag("current") == true)
            }
            filesChanged = fields.count("files_changed")
            issues = fields.count("issues")
            isRepairable = fields.flag("repairable") == true
            requirements = (fields.list("requirements") ?? []).prefix(10).compactMap { value -> Requirement? in
                guard let entry = ViewFields(value), let text = entry.text("text", 160) else { return nil }
                return Requirement(text: text, state: entry.word("state"))
            }
            unmet = fields.count("unmet")
            wasRepaired = fields.flag("repaired") == true
        }
    }

    /// A card to review, in place. Its real card is the review card the conversation already shows.
    public struct Review: Sendable, Hashable {
        public enum DecidedBy: String, Sendable, Hashable {
            case you
            /// Pebble's check matched the person's own words (`quote`).
            case pebble
            /// The permission mode allowed it.
            case mode
        }
        public var actionID: String?
        /// The card's kind.
        public var action: String?
        public var state: WorkState?
        public var decidedBy: DecidedBy?
        /// The person's words Pebble's check matched.
        public var quote: String?

        init(_ fields: ViewFields) {
            actionID = fields.text("action_id", 64)
            action = fields.text("action", 24)
            state = fields.word("state")
            decidedBy = fields.word("decided_by")
            quote = fields.text("quote", 200)
        }
    }

    /// A question to the person. Its real card is the question the conversation already shows.
    public struct Question: Sendable, Hashable {
        /// How many questions.
        public var questions: Int?
        public var state: WorkState?

        init(_ fields: ViewFields) {
            questions = fields.count("questions")
            state = fields.word("state")
        }
    }
}

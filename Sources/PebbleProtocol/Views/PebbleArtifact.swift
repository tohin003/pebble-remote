import Foundation

/// One of a conversation's views as Pebble keeps it: `get_chat`'s `artifacts`, `artifact_get`'s answer, and what an
/// `artifact` event names (types.ts `ArtifactBase` with its kind and data). Read tolerantly: a row without its id is
/// nil; everything else falls back to what is known.
public struct PebbleArtifact: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable {
        case ready
        /// An html view waiting for the person's review on the Mac.
        case review
        case stopped
        case expired
    }

    /// The question a form's answers settle (`form_question`): a pending form blocks its task.
    public struct FormQuestion: Sendable, Hashable {
        public var id: String
        public var revision: Int
        /// pending, answered or cancelled.
        public var status: String
        /// The answers given, by field id.
        public var answers: [String: FormAnswer]

        public init(id: String, revision: Int = 1, status: String = "pending", answers: [String: FormAnswer] = [:]) {
            self.id = id
            self.revision = revision
            self.status = status
            self.answers = answers
        }

        public var isPending: Bool { status == "pending" }
    }

    /// One field's answer: a chosen option or written words, never both (interaction.canonical_answer).
    public enum FormAnswer: Sendable, Hashable {
        case option(String)
        case text(String)

        init?(_ json: JSONValue?) {
            if let option = json?["option_id"]?.string, !option.isEmpty {
                self = .option(option)
            } else if let words = json?["text"]?.string {
                self = .text(words)
            } else {
                return nil
            }
        }

        /// As Pebble's routes take it.
        public var json: JSONValue {
            switch self {
            case .option(let id): ["option_id": .string(id)]
            case .text(let words): ["text": .string(words)]
            }
        }
    }

    public var id: String
    public var chatID: String
    /// The model's title, as display text; nil when it sent none.
    public var title: String?
    /// The kind as Pebble sent it (form, table … or one this version doesn't know).
    public var kind: String
    public var revision: Int
    public var status: Status?
    public var created: Date?
    public var updated: Date?
    /// The run that drew it.
    public var ownerRunID: String?
    public var formQuestion: FormQuestion?
    public var view: NativeView

    public init?(json: JSONValue, chatID fallback: String? = nil) {
        guard let fields = ViewFields(json), let id = fields.object["id"]?.string, !id.isEmpty,
            let chat = fields.object["chat_id"]?.string ?? fallback, !chat.isEmpty
        else { return nil }
        self.id = id
        chatID = chat
        title = fields.text("title", 120)
        kind = fields.object["kind"]?.string ?? ""
        revision = max(1, fields.count("revision") ?? 1)
        status = fields.word("status")
        created = fields.amount("created").map { Date(timeIntervalSince1970: $0) }
        updated = fields.amount("updated").map { Date(timeIntervalSince1970: $0) }
        ownerRunID = fields.object["owner_run_id"]?.string
        if let question = fields.nested("form_question"), let questionID = question.object["id"]?.string {
            var answers: [String: FormAnswer] = [:]
            for (field, value) in question.object["answer"]?.object ?? [:] {
                if let answer = FormAnswer(value) { answers[field] = answer }
            }
            formQuestion = FormQuestion(
                id: questionID, revision: question.count("revision") ?? 1,
                status: question.object["status"]?.string ?? "pending", answers: answers)
        }
        var view = NativeView(kind: kind, data: fields.object["data"])
        if case .dashboard(let dashboard) = view {
            view = .dashboard(dashboard.resolving(fields.object["bindings"]))
        }
        self.view = view
    }

    /// Stopped and expired views no longer change, ask or refresh.
    public var isLive: Bool { status != .stopped && status != .expired }

    /// A form whose question waits for the person: its task is blocked until it is answered.
    public var waitsForAnswer: Bool { kind == "form" && isLive && formQuestion?.isPending == true }

    /// The form, when this view is one.
    public var form: NativeView.Form? {
        if case .form(let form) = view { form } else { nil }
    }
}

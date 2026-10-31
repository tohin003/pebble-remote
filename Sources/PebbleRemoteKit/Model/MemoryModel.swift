import Foundation
import PebbleProtocol

// Lane Z, item 4: what Pebble remembers, as its Memory settings show it (AdvancedSettings.vue, MemoryContests.vue;
// app.py memory_list, memory_contests). Records are Pebble's data: the screens show their words literally.

/// One saved memory, as `memory_list` gives it: a row of Pebble's memories with its learning status and proof. In the
/// working layer, one of the newest task checkpoints (its id is the conversation's).
public struct MemoryRecord: Sendable, Hashable, Identifiable {
    public var id: String
    /// The layer: working, episodic, semantic, procedural, temporal or profile.
    public var kind: String
    /// Pebble's stored text: words, or JSON for a checkpoint, a task's result, a quote or a recipe. The screen says it
    /// in words (`AppCopy.Memories.text`).
    public var content: String
    /// "global" (personal), "chat:<id>" (a conversation) or a project's folder.
    public var scope: String
    public var chatID: ChatID?
    /// Where it came from: direct-user, user, curated, imported, broker, conversation, auto-learned.
    public var origin: String
    public var updated: Date?
    public var expires: Date?
    /// "contested", "superseded" or "promoted" when Pebble's learning holds it.
    public var learningStatus: String?
    /// The class of evidence Pebble learned it from ("human_preference", "attributed_file_quote", …), if any.
    public var evidenceClass: String?

    public init(
        id: String, kind: String, content: String, scope: String = "global", chatID: ChatID? = nil,
        origin: String = "user", updated: Date? = nil, expires: Date? = nil, learningStatus: String? = nil,
        evidenceClass: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.content = content
        self.scope = scope
        self.chatID = chatID
        self.origin = origin
        self.updated = updated
        self.expires = expires
        self.learningStatus = learningStatus
        self.evidenceClass = evidenceClass
    }

    public init?(json: JSONValue) {
        guard let id = json["id"]?.string, !id.isEmpty, let kind = json["kind"]?.string else { return nil }
        self.init(
            id: id, kind: kind, content: json["content"]?.string ?? "", scope: json["scope"]?.string ?? "",
            chatID: json["chat_id"]?.string, origin: json["origin"]?.string ?? "", updated: unixDate(json["updated"]),
            expires: unixDate(json["expires"]), learningStatus: json["learning_status"]?.string,
            evidenceClass: Self.evidenceClass(json["provenance"]?.string))
    }

    /// The proof's `evidence_class` (AdvancedSettings.vue `provenanceClass`); nil when the proof is missing or unreadable.
    static func evidenceClass(_ provenance: String?) -> String? {
        guard let data = provenance?.data(using: .utf8), let proof = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return proof["evidence_class"]?.string
    }
}

/// One page of a layer's memories, newest first.
public struct MemoryPage: Sendable, Hashable {
    public var records: [MemoryRecord]
    /// A full page came back: "Load More" reads the next.
    public var hasMore: Bool

    public init(records: [MemoryRecord], hasMore: Bool) {
        self.records = records
        self.hasMore = hasMore
    }
}

/// Memories that disagree, waiting for the person (`memory_contests`): while they do, Pebble recalls neither as
/// current.
public struct ContestedMemory: Sendable, Hashable, Identifiable {
    public struct Record: Sendable, Hashable, Identifiable {
        public var memoryID: String
        public var kind: String
        /// The claim's topic, when Pebble names one; "model_lesson_unverified" for a lesson the model suggested.
        public var label: String?
        /// At most 2,000 characters, as Pebble's window keeps them.
        public var content: String
        public var scope: String
        public var origin: String
        public var created: Date?
        public var id: String { memoryID }

        public init(
            memoryID: String, kind: String, label: String? = nil, content: String, scope: String = "global",
            origin: String = "", created: Date? = nil
        ) {
            self.memoryID = memoryID
            self.kind = kind
            self.label = label
            self.content = content
            self.scope = scope
            self.origin = origin
            self.created = created
        }

        init?(json: JSONValue) {
            guard let id = json["memory_id"]?.string, !id.isEmpty else { return nil }
            let content = json["content"]?.string ?? ""
            self.init(
                memoryID: id, kind: json["kind"]?.string ?? "", label: json["label"]?.string,
                content: content.count > 2000 ? String(content.prefix(2000)) + "\u{2026}" : content,
                scope: json["scope"]?.string ?? "", origin: json["origin"]?.string ?? "", created: unixDate(json["created"]))
        }
    }

    /// The contested memory.
    public var record: Record
    /// The memories that disagree with it.
    public var counterparts: [Record]
    public var id: String { record.memoryID }

    public init(record: Record, counterparts: [Record]) {
        self.record = record
        self.counterparts = counterparts
    }

    init?(json: JSONValue) {
        guard let record = Record(json: json) else { return nil }
        self.init(record: record, counterparts: (json["counterparts"]?.array ?? []).compactMap(Record.init(json:)))
    }
}

/// The person's decision on a contest (MemoryContests.vue): Keep this forgets the memories that disagree with it, Remove
/// this forgets this one, Keep both forgets nothing (and the disagreement is not contested again).
public enum ContestDecision: String, Sendable, Hashable, CaseIterable {
    case keep
    case reject
    case keepBoth = "keep_both"

    /// What the decision forgets, for good.
    public func forgets(in contest: ContestedMemory) -> [ContestedMemory.Record] {
        switch self {
        case .keep: contest.counterparts
        case .reject: [contest.record]
        case .keepBoth: []
        }
    }
}

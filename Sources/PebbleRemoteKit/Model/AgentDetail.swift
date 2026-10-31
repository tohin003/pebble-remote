import Foundation
import PebbleProtocol

// Lane T (2026-10-31): one helper agent as `agent_get` reads it (agent_manager.py `get`: agent_tree.py `_public` plus
// its records), for the agent's own screen in Details › Task (AgentPanel.vue's selected agent).

/// A helper agent in full: what a person reads first (its task, state, use and result), and the technical details
/// Pebble folds away (ids, generation, tools, limits, paths, records).
public struct AgentDetail: Sendable, Hashable {
    /// A name and its value, as Pebble's tables list them ("max steps", "8").
    public struct Fact: Sendable, Hashable, Identifiable {
        public var name: String
        public var value: String
        public var id: String { name }

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// One of the records Pebble keeps for the agent, counted (AgentPanel.vue `collections`).
    public struct Records: Sendable, Hashable, Identifiable {
        /// receipts, messages, questions, patches or effects (agent_manager.py's keys).
        public var key: String
        public var count: Int
        public var id: String { key }

        public init(key: String, count: Int) {
            self.key = key
            self.count = count
        }
    }

    /// The agent as `agent_list` lists it: name, task, state, result, tokens and seconds.
    public var node: AgentNode
    public var generation: Int?
    public var tools: [String]
    public var limits: [Fact]
    public var writePaths: [String]
    public var dependencies: [String]
    public var evidence: [String]
    public var review: String?
    /// Model calls it made.
    public var dispatches: Int?
    /// Why it failed, in Pebble's words.
    public var error: String?
    /// A result Pebble kept as a record rather than as text: its plain fields (the text is `node.result`).
    public var resultFacts: [Fact]
    public var records: [Records]

    public init(
        node: AgentNode, generation: Int? = nil, tools: [String] = [], limits: [Fact] = [], writePaths: [String] = [],
        dependencies: [String] = [], evidence: [String] = [], review: String? = nil, dispatches: Int? = nil,
        error: String? = nil, resultFacts: [Fact] = [], records: [Records] = []
    ) {
        self.node = node
        self.generation = generation
        self.tools = tools
        self.limits = limits
        self.writePaths = writePaths
        self.dependencies = dependencies
        self.evidence = evidence
        self.review = review
        self.dispatches = dispatches
        self.error = error
        self.resultFacts = resultFacts
        self.records = records
    }

    /// The record kinds, in AgentPanel.vue's order.
    public static let recordKeys = ["receipts", "messages", "questions", "patches", "effects"]  // lint-copy: allow

    public init?(json: JSONValue, runID: RunID) {
        guard let node = AgentNode(json: json, runID: runID) else { return nil }
        let result = json["result"]
        var resultFacts: [Fact] = []
        if case .object(let record)? = result {
            resultFacts = Self.facts(record).filter { $0.name != "text" }
        }
        self.init(
            node: node, generation: json["generation"]?.int, tools: Self.texts(json["tools"]),
            limits: Self.facts(json["limits"]?.object ?? [:]), writePaths: Self.texts(json["write_paths"]),
            dependencies: Self.texts(json["dependencies"]), evidence: Self.texts(json["evidence_ids"]),
            review: json["review"]?.string.flatMap { $0.isEmpty ? nil : $0 }, dispatches: json["dispatches"]?.int,
            error: json["error"]?.string.flatMap { $0.isEmpty ? nil : $0 }, resultFacts: resultFacts,
            records: Self.recordKeys.compactMap { key in
                guard let count = json[key]?.array?.count, count > 0 else { return nil }
                return Records(key: key, count: count)
            })
    }

    /// Strings only, as Pebble's `strings()` keeps them.
    static func texts(_ value: JSONValue?) -> [String] { (value?.array ?? []).compactMap(\.string) }

    /// Plain values only (text, yes or no, finite numbers), at most 32, in key order (AgentPanel.vue `scalarEntries`;
    /// a JSON object carries no order, so the phone sorts the names).
    static func facts(_ object: [String: JSONValue]) -> [Fact] {
        object.keys.sorted().compactMap { key -> Fact? in
            let name = key.replacingOccurrences(of: "_", with: " ")
            switch object[key] {
            case .string(let text)?: return Fact(name: name, value: text)
            case .bool(let flag)?: return Fact(name: name, value: flag ? "true" : "false")
            case .int(let number)?: return Fact(name: name, value: String(number))
            case .double(let number)? where number.isFinite: return Fact(name: name, value: Self.number(number))
            default: return nil
            }
        }
        .prefix(32).map { $0 }
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

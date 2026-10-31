import Foundation
import PebbleProtocol

// Lane Z, item 4: Settings › Memory, as Pebble's Memory settings read and change it (AdvancedSettings.vue,
// MemoryContests.vue). Reads return their values to the screen, which keeps them; every change asks Pebble again.

extension RemoteStore {
    /// Memories per page, as Pebble's window reads them (MEMORY_PAGE).
    public nonisolated static let memoryPage = 100

    /// One page of a layer's memories, newest first (`memory_list`). The working layer is the newest task checkpoints:
    /// Pebble takes no search or page there, so the screen searches them by their words. Other layers take Pebble's
    /// search (every word, at most 200 characters) and pages of 100; `shown` is how many the screen holds already.
    public func memories(in layer: String, matching query: String = "", after shown: Int = 0) async throws -> MemoryPage {
        var params: [String: JSONValue] = ["kind": .string(layer)]
        if layer != "working" {
            let words = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            if !words.isEmpty { params["query"] = .string(words) }
            params["offset"] = .int(shown)
            params["limit"] = .int(Self.memoryPage)
        }
        let result = try await answer("memory_list", .object(params))
        let rows = (result.array ?? []).compactMap(MemoryRecord.init(json:))
        return MemoryPage(records: rows, hasMore: layer != "working" && rows.count == Self.memoryPage)
    }

    /// Forgets a memory for good (`memory_delete {id, kind}`), and Pebble won't learn it again from the same place.
    /// Face ID, as the bridge elevates it (contract 3.6, `welcome.elevated`); Pebble refuses while a task runs.
    /// `words` are the memory's words as the screen shows them, for Face ID's sentence.
    public func forget(_ memory: MemoryRecord, words: String) async throws {
        _ = try await act(
            "memory_delete", ["id": .string(memory.id), "kind": .string(memory.kind)],
            reason: StoreWords.forgetMemoryReason(words))
        requestState()  // the layers' counts
    }

    /// The memories that disagree and wait for the person (`memory_contests`).
    public func contestedMemories() async throws -> [ContestedMemory] {
        let result = try await answer("memory_contests", [:])
        return (result["groups"]?.array ?? []).compactMap(ContestedMemory.init(json:))
    }

    /// The person's decision on a contest (`memory_resolve_contest {memory_id, decision}`), after the screen showed what
    /// it forgets. Face ID only where the bridge elevates it (F3 asked for it; contract 3.6 doesn't list it today).
    /// Returns how many memories Pebble forgot, or nil when its answer doesn't say. Pebble refuses while a task runs.
    @discardableResult
    public func resolve(_ contest: ContestedMemory, _ decision: ContestDecision, question: String) async throws -> Int? {
        let result = try await act(
            "memory_resolve_contest", ["memory_id": .string(contest.id), "decision": .string(decision.rawValue)],
            reason: StoreWords.decideMemoryReason(question))
        requestState()
        return result["forgotten"]?.array?.count
    }
}

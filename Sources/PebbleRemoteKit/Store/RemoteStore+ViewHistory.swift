import Foundation
import PebbleProtocol

// Lane T (2026-10-31): a view's saved revisions and Stop (ArtifactPanel.vue `loadArtifact`, `stopArtifact`; app.py
// `artifact_history(chat_id, id)`, `artifact_get(chat_id, id, revision)`, `artifact_stop(chat_id, id, revision)`).
// `artifact_get` is one of the bridge's reads; `artifact_history` and `artifact_stop` need the unlock.

extension RemoteStore {
    /// Every saved revision of a view, oldest first. Pebble checks each is this view's; so does the phone.
    public func viewHistory(_ view: PebbleArtifact) async throws -> [PebbleArtifact] {
        let result = try await answer("artifact_history", ["chat_id": .string(view.chatID), "id": .string(view.id)])
        guard let rows = result.array else { throw report(unreadable()) }
        let history = rows.compactMap { PebbleArtifact(json: $0, chatID: view.chatID) }
        guard history.count == rows.count, history.allSatisfy({ $0.id == view.id && $0.chatID == view.chatID }) else {
            throw report(unreadable())
        }
        return history.sorted { $0.revision < $1.revision }
    }

    /// An earlier revision, to read only. The conversation keeps the current one: this copy is never remembered.
    public func readRevision(_ revision: Int, of view: PebbleArtifact) async throws -> PebbleArtifact {
        let params: JSONValue = ["chat_id": .string(view.chatID), "id": .string(view.id), "revision": .int(revision)]
        let result = try await answer("artifact_get", params)
        guard let earlier = PebbleArtifact(json: result, chatID: view.chatID), earlier.id == view.id,
            earlier.revision == revision
        else { throw report(unreadable()) }
        return earlier
    }

    /// Stop a live view (CV-09): Pebble saves it as a new, stopped revision; a form stops asking (its question is
    /// cancelled, and a task that needs the answer stops), and a dashboard stops refreshing. It can't be undone.
    public func stopView(_ view: PebbleArtifact) async throws -> PebbleArtifact {
        let params: JSONValue = [
            "chat_id": .string(view.chatID), "id": .string(view.id), "revision": .int(view.revision),
        ]
        let result = try await act("artifact_stop", params, reason: ViewHistoryWords.stopReason(view.title))
        guard let stopped = PebbleArtifact(json: result, chatID: view.chatID), stopped.id == view.id else {
            throw report(unreadable())
        }
        publish(world.remember(stopped))
        if transcripts[view.chatID] != nil { requestChat(view.chatID) }  // the cancelled question, the stopped task
        return stopped
    }
}

/// What Face ID says, should the bridge ever ask for it on Stop. A title comes from a model: one plain line.
public enum ViewHistoryWords {
    public static func stopReason(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "Stop Pebble's view" }
        return "Stop Pebble's view \u{201C}\(StoreWords.detail(title))\u{201D}"
    }
}

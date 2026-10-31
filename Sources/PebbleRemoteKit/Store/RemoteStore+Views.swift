import Foundation
import PebbleProtocol

// Lane G (2026-10-31): the calls behind Pebble's views (contract 3.12). Calls and params are Pebble's own (read-only
// Pebble checkout, app.py): `artifact_get(chat_id, id, revision=None)` is a read (C1: no unlock);
// `artifact_submit(chat_id, id, revision, answers)` and `artifact_refresh(chat_id, id, revision)` need the unlock and an
// idem, and no Face ID proof (3.6 doesn't list them), unless the bridge's `welcome.elevated` does.

extension RemoteStore {
    /// `run_activity`'s cursor past every item: the answer then carries only the header, the summary and any running
    /// item (run_activity.py `read`).
    static let pastEveryItem = 1_000_000_000

    /// A view as Pebble keeps it now, decorated (a form's question, a dashboard's live panels). The conversation's
    /// copy is replaced. Quiet: a failure is returned, never shown on its own.
    public func readView(_ id: String, in chat: ChatID) async throws -> PebbleArtifact {
        let result = try await client.call("artifact_get", ["chat_id": .string(chat), "id": .string(id)])
        guard let artifact = PebbleArtifact(json: result, chatID: chat), artifact.id == id, artifact.chatID == chat else {
            throw unreadable()
        }
        publish(world.remember(artifact))
        return artifact
    }

    /// "Submit answers": a Pebble form's answers become task input in its conversation (artifact_inputs.submit; the
    /// same question and answer rules as `question_answer`). Pebble refuses a stale or stopped form in its own words.
    public func submit(_ answers: [String: PebbleArtifact.FormAnswer], to form: PebbleArtifact) async throws {
        let params: JSONValue = [
            "chat_id": .string(form.chatID), "id": .string(form.id), "revision": .int(form.revision),
            "answers": .object(answers.mapValues(\.json)),
        ]
        _ = try await act("artifact_submit", params, reason: ViewsWords.submitReason(form.title))
        publish(world.markAnswered(form, with: answers))
        if transcripts[form.chatID] != nil { requestChat(form.chatID) }  // ArtifactPanel reads the view back
    }

    /// "Refresh Data": Pebble reads a live dashboard's panels again (a read on the Mac that writes nothing).
    public func refreshDashboard(_ view: PebbleArtifact) async throws -> PebbleArtifact {
        let params: JSONValue = ["chat_id": .string(view.chatID), "id": .string(view.id), "revision": .int(view.revision)]
        let result = try await act("artifact_refresh", params, reason: ViewsWords.refreshReason)
        guard let fresh = PebbleArtifact(json: result, chatID: view.chatID), fresh.id == view.id else { throw unreadable() }
        publish(world.remember(fresh))
        return fresh
    }

    /// A run's header and summary without its items (`run_activity` past every item). Quiet: nil when the read fails.
    public func workReceipt(of run: RunID) async -> (header: WorkHeader?, summary: WorkSummary?)? {
        guard offers("run_activity"),
            let page = try? await client.call("run_activity", ["run_id": .string(run), "after": .int(Self.pastEveryItem)])
        else { return nil }
        return (WorkHeader(json: page["header"]), WorkSummary(json: page["summary"]))
    }

    /// A conversation's views, as the phone holds them (oldest first).
    public func views(in chat: ChatID) -> [PebbleArtifact] { world.views(in: chat) }
}

/// What Face ID says if the bridge ever asks for it on a view's call (Kit can't read PebbleDesign's copy). A title comes
/// from a model, so it is one plain line (StoreWords.detail).
public enum ViewsWords {
    public static func submitReason(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "Answer Pebble's form" }
        return "Answer Pebble's form \u{201C}\(StoreWords.detail(title))\u{201D}"
    }
    public static let refreshReason = "Refresh a dashboard's data"
    /// Lane Q: a quiz's calls, should the bridge ever ask (it asks only for the share).
    public static func takeQuizReason(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "Take Pebble's quiz" }
        return "Take Pebble's quiz \u{201C}\(StoreWords.detail(title))\u{201D}"
    }
    /// Lane Q: "Share result with Pebble" always asks for Face ID (remote_policy.py `OPEN_ON_MAC`).
    public static let shareQuizReason = "Share your quiz result with Pebble"
}

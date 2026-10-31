import Foundation
import PebbleProtocol

// Lane T (2026-10-31): exporting a view, as Pebble's export section does (ExportPanel.vue; app.py
// `export_preview(chat_id, source, format, options)`, `export_render(chat_id, plan_id)`, `export_cancel(chat_id,
// plan_id)`, `export_discard(chat_id, export_id)`, `export_list(chat_id)`, `export_get(chat_id, export_id)`). Each
// needs the unlock; none is elevated. Save (`export_save`) opens the Mac's Save dialog and is excluded on the phone
// (contract 3.7), and no allowed method returns the file's bytes, so the phone can't offer Share yet.

extension RemoteStore {
    /// Preview export: Pebble checks what the file would hold and pins the view's revision. Nothing is written.
    public func previewExport(
        of view: PebbleArtifact, as format: ExportFormat, includeAnswers: Bool
    ) async throws -> ExportPlan {
        let source: JSONValue = ["kind": "artifact", "id": .string(view.id), "revision": .int(view.revision)]
        // The Mac sends the answer key's choice only for a quiz (ExportPanel.vue `options`).
        let options: JSONValue = view.kind == "quiz" ? ["include_answers": .bool(includeAnswers)] : [:]
        let params: JSONValue = [
            "chat_id": .string(view.chatID), "source": source, "format": .string(format.rawValue), "options": options,
        ]
        let result = try await act("export_preview", params, reason: ExportWords.previewReason)
        guard let plan = ExportPlan(json: result, asked: format) else { throw report(unreadable()) }
        return plan
    }

    /// Create file: Pebble makes the file on the Mac and reads it back. The answer comes once it is done (or
    /// cancelled); a plan works once.
    public func renderExport(_ plan: ExportPlan, in chat: ChatID) async throws -> ExportResult {
        let params: JSONValue = ["chat_id": .string(chat), "plan_id": .string(plan.id)]
        let result = try await act("export_render", params, reason: ExportWords.createReason)
        guard let made = ExportResult(json: result) else { throw report(unreadable()) }
        return made
    }

    /// Cancel while Pebble makes the file: Create file then answers "cancelled" and the partial file is removed.
    /// False when nothing was being made any more.
    @discardableResult
    public func cancelExport(_ plan: ExportPlan, in chat: ChatID) async throws -> Bool {
        let params: JSONValue = ["chat_id": .string(chat), "plan_id": .string(plan.id)]
        return try await act("export_cancel", params, reason: ExportWords.cancelReason).bool ?? false
    }

    /// Delete Pebble's copy: the file Pebble made goes (with its Documents copy); files saved elsewhere stay.
    public func discardExport(_ id: String, in chat: ChatID) async throws {
        let params: JSONValue = ["chat_id": .string(chat), "export_id": .string(id)]
        _ = try await act("export_discard", params, reason: ExportWords.discardReason)
    }

    /// The conversation's exports, newest first (Pebble lists the latest 50).
    public func exports(in chat: ChatID) async throws -> [ExportResult] {
        let result = try await answer("export_list", ["chat_id": .string(chat)])
        guard let rows = result.array else { throw report(unreadable()) }
        return rows.compactMap(ExportResult.init(json:))
    }

    /// One export in full, with the copies saved from the Mac.
    public func export(_ id: String, in chat: ChatID) async throws -> ExportResult {
        let result = try await answer("export_get", ["chat_id": .string(chat), "export_id": .string(id)])
        guard let found = ExportResult(json: result), found.id == id else { throw report(unreadable()) }
        return found
    }
}

/// What Face ID says, should the bridge ever ask for it on an export's call.
public enum ExportWords {
    public static let previewReason = "Preview an export on your Mac"
    public static let createReason = "Make an export file on your Mac"
    public static let cancelReason = "Cancel an export"
    public static let discardReason = "Delete Pebble's copy of an export"
}

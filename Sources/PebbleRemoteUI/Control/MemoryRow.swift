import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One saved memory, as Pebble's Memory settings show it: where it came from, whose it is, its conversation, when and
/// what learning says, over its words (AdvancedSettings.vue `memoryMeta`, `memoryText`). The words are Pebble's data:
/// shown literally and in full, never as a link or a button.
struct MemoryRow: View {
    let record: MemoryRecord
    /// The title of the conversation it came from, when the phone knows it.
    let chatTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(verbatim: meta)
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
            Text(verbatim: AppCopy.Memories.text(kind: record.kind, content: record.content, scope: record.scope))
                .font(PebbleFont.message)
                .foregroundStyle(PebbleColor.text)
        }
        .padding(.vertical, PebbleSpace.s1)
        .accessibilityElement(children: .combine)
    }

    private var meta: String {
        AppCopy.Memories.meta(
            origin: AppCopy.Memories.origin(
                record.origin, kind: record.kind, evidenceClass: record.evidenceClass, id: record.id),
            scope: record.scope, chatTitle: chatTitle, updated: record.updated, learningStatus: record.learningStatus,
            expires: record.expires)
    }
}

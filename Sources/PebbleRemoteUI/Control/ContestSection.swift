import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One contested memory as a decision (MemoryContests.vue): the memory, the ones that disagree with it, then Pebble's
/// three choices, each confirmed first with exactly what it forgets. Remove This forgets the memory itself, so it is
/// destructive. The records are Pebble's data and show as literal text.
struct ContestSection: View {
    let contest: ContestedMemory
    /// Pebble takes decisions now (no task runs, the bridge offers it, none is under way).
    let canDecide: Bool
    let ask: (ContestedMemory, ContestDecision) -> Void

    var body: some View {
        Section {
            ContestRecordRow(record: contest.record, role: AppCopy.Memories.contestedRecord)
            ForEach(contest.counterparts) { record in
                ContestRecordRow(record: record, role: AppCopy.Memories.disagrees)
            }
            ForEach(ContestDecision.allCases, id: \.self) { decision in
                Button(AppCopy.Memories.decision(decision.rawValue), role: decision == .reject ? .destructive : nil) {
                    ask(contest, decision)
                }
                .disabled(!canDecide)
            }
        }
    }
}

/// A record in a contest: its role and where it came from, its topic, then its words.
private struct ContestRecordRow: View {
    let record: ContestedMemory.Record
    let role: String

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(role + " \u{00B7} " + details)
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
            if let topic = AppCopy.Memories.topic(record.label) {
                Text(topic)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: record.content)
                .font(PebbleFont.message)
                .foregroundStyle(PebbleColor.text)
        }
        .padding(.vertical, PebbleSpace.s1)
        .accessibilityElement(children: .combine)
    }

    /// Its layer, whose it is, where it came from (in words, never Pebble's code) and when.
    private var details: String {
        AppCopy.Memories.details(
            kind: record.kind, scope: record.scope,
            origin: AppCopy.Memories.origin(record.origin, kind: record.kind, evidenceClass: nil, id: record.memoryID),
            created: record.created)
    }
}

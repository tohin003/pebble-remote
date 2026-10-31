import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A settled run's end line with its summary under it (WorkView.vue's summary): files changed, commands, tests, the
/// check's verdict and the tokens, as chips. The end line already says how long it took, so the time isn't repeated.
/// Pebble's summary is read once, quietly (`run_activity` past every item); nothing more shows when there is none.
struct WorkRunEnd<EndLine: View>: View {
    let runID: RunID
    let endLine: EndLine
    @Environment(RemoteStore.self) private var store
    @State private var summary: WorkSummary?

    init(runID: RunID, @ViewBuilder endLine: () -> EndLine) {
        self.runID = runID
        self.endLine = endLine()
        _summary = State(initialValue: WorkReceipts.summaries[runID])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            endLine
            if let summary {
                WorkSummaryChips(summary: summary)
            }
        }
        .task(id: runID) { await load() }
    }

    private func load() async {
        guard summary == nil, !WorkReceipts.none.contains(runID), store.bridgeOffers("run_activity") else { return }
        guard let receipt = await store.workReceipt(of: runID) else { return }
        if let found = receipt.summary, !found.isEmpty {
            WorkReceipts.summaries[runID] = found
            summary = found
        } else {
            WorkReceipts.none.insert(runID)
        }
    }
}

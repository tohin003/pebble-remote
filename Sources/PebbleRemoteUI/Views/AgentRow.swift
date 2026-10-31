import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One child agent: its name, its state, and what it took.
struct AgentRow: View {
    let agent: WorkView.Agent
    @ScaledMetric(relativeTo: .footnote) private var indent: CGFloat = 14

    var body: some View {
        let took = [
            RunCopy.formatDuration(agent.seconds), agent.tokens.flatMap { $0 > 0 ? AppCopy.Views.tokens($0) : nil },
        ].compactMap { $0 }.joined(separator: " \u{00B7} ")
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                Text(verbatim: agent.name ?? "")
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
                if let state = agent.state {
                    ToneLabel(AppCopy.Views.state(state), tone: state.tone)
                }
            }
            if !took.isEmpty {
                Text(took)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
        .padding(.leading, CGFloat(min(3, max(0, (agent.depth ?? 1) - 1))) * indent)
        .accessibilityElement(children: .combine)
    }
}

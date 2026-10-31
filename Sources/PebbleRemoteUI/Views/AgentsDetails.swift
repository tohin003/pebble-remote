import PebbleDesign
import PebbleProtocol
import SwiftUI

/// Child agents (WorkCard.vue): each name (literal), indented by depth, its state in words, and its time and tokens.
struct AgentsDetails: View {
    let agents: [WorkView.Agent]
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ForEach(Array(agents.prefix(showsAll ? agents.count : ShowMoreButton.shown).enumerated()), id: \.offset) {
                _, agent in
                AgentRow(agent: agent)
            }
            if agents.count > ShowMoreButton.shown {
                ShowMoreButton(hidden: agents.count - ShowMoreButton.shown, showsAll: $showsAll)
            }
        }
    }
}

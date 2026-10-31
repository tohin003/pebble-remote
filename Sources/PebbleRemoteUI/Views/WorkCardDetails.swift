import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// What a card holds, by kind (WorkCard.vue's sections), shown when the person opens the card.
struct WorkCardDetails: View {
    let card: WorkCard<RunActivityItem>
    let runIsLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            switch card.kind {
            case .explored:
                ExploredDetails(views: card.views)
            case .web:
                WebDetails(queries: card.webQueries, sites: card.webSites)
            case .files:
                FilesDetails(changes: card.fileChanges)
            case .command:
                if case .command(let command)? = card.views.first?.content {
                    CommandDetails(command: command)
                }
            case .tests:
                if case .tests(let tests)? = card.views.first?.content {
                    TestsDetails(tests: tests)
                }
            case .git:
                if case .git(let git)? = card.views.first?.content {
                    GitDetails(git: git)
                }
            case .window:
                WindowDetails(windows: card.views.compactMap { if case .window(let window) = $0.content { window } else { nil } })
            case .agents:
                AgentsDetails(agents: card.views.compactMap { if case .agent(let agent) = $0.content { agent } else { nil } })
            case .checks:
                if case .checks(let checks)? = card.views.first?.content {
                    ChecksDetails(checks: checks)
                }
            }
            // A failed command or test run keeps Pebble's own words for it (WorkCard.vue).
            if card.kind == .command || card.kind == .tests, let item = card.items.last, item.status == "failed",
                let detail = item.detail
            {
                Text(verbatim: detail)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

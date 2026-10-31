import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// How many cards, questions and task decisions wait, the oldest one's chat, and a way to the Reviews tab.
struct ReviewSummaryRow: View {
    let waiting: [WaitingItem]
    @Environment(Router.self) private var router

    var body: some View {
        Button(action: openReviews) {
            HStack {
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(AppCopy.Accessibility.waitingItems(waiting.count))
                        .font(.headline)
                    if let first = waiting.first {
                        Text(Self.title(of: first))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppCopy.Home.seeAll)
    }

    private func openReviews() {
        router.open(.reviews)
    }

    private static func title(of item: WaitingItem) -> String {
        switch item {
        case .review(let review): review.title
        case .question(let card): card.prompts.first?.title ?? card.chatTitle
        case .task(let task): RecoveryCopy.Task.sentence(task.state, windowChecked: task.windowChecked)
        }
    }
}

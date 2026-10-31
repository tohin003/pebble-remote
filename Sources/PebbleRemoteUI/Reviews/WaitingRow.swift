import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One waiting item: its chat (tap to open it), then the card, the question, or the task Pebble holds for a decision.
struct WaitingRow: View {
    let item: WaitingItem
    /// Opens a card's details or a task's uncertain outcomes on the Reviews tab.
    var present: RecoveryPresenter? = nil
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Button {
                router.push(item.chatID)
            } label: {
                Label(AppCopy.Reviews.inConversation(item.chatTitle), systemImage: PebbleSymbol.conversation)
                    .font(.footnote)
                    .lineLimit(1)
                    .frame(minHeight: PebbleSize.minTap, alignment: .leading)
            }
            .buttonStyle(.borderless)
            switch item {
            case .review(let review):
                ReviewItemCard(item: review, present: present)
            case .question(let card):
                QuestionCardForm(card: card)
            case .task(let task):
                TaskCard(task: task, present: present, inConversation: false)
            }
        }
    }
}

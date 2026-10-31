import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A question Pebble asked (AskUserQuestion), wired to the store: PebbleDesign's QuestionCardView with the card's
/// prompts; sending answers through `question_answer`, dismissing through `question_cancel`.
struct QuestionCardForm: View {
    let card: QuestionCard
    /// The chat's title above the card (the Reviews tab lists questions from every chat).
    var showsConversation = false
    @Environment(RemoteStore.self) private var store
    @State private var isBusy = false
    @State private var dismissals = 0

    var body: some View {
        // Lane G: a question that belongs to a live Pebble form shows as the form (answered with `artifact_submit`).
        if let form = card.form, form.isLive, form.form != nil {
            FormWaitingCard(card: card, form: form)
        } else {
            QuestionCardView(
                prompts: card.prompts.map(Self.prompt), required: card.required,
                conversation: showsConversation ? card.chatTitle : nil, requester: card.requester, isBusy: isBusy,
                onSend: send, onDismiss: dismissCard)
            .sensoryFeedback(PebbleHaptics.rejected, trigger: dismissals)
        }
    }

    /// The card's prompts in PebbleDesign's terms.
    static func prompt(_ prompt: QuestionCard.Prompt) -> QuestionCardView.Prompt {
        QuestionCardView.Prompt(
            id: prompt.id, title: prompt.title,
            options: prompt.options.map { .init(id: $0.id, label: $0.label, detail: $0.detail) },
            allowsFreeText: prompt.allowsFreeText)
    }

    /// The person's answers in the store's terms.
    static func answers(_ answers: [String: QuestionCardView.Answer]) -> [String: QuestionAnswer] {
        answers.mapValues { answer in
            switch answer {
            case .option(let id): .option(id: id)
            case .text(let text): .text(text)
            }
        }
    }

    private func send(_ chosen: [String: QuestionCardView.Answer]) {
        let answers = Self.answers(chosen)
        guard !answers.isEmpty, !isBusy else { return }
        isBusy = true
        Task {
            await store.attempt { try await store.answer(card, with: answers) }
            isBusy = false
        }
    }

    private func dismissCard() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            if await store.attempt({ try await store.dismiss(card) }) { dismissals += 1 }
            isBusy = false
        }
    }
}

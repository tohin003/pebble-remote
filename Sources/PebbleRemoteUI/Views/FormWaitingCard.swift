import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A Pebble form that waits for the person, in place: in its conversation and on Reviews (IA rule 5). A form is a
/// question in disguise that blocks its task, so this card stands where the question's card would: the form's title,
/// what it asks, "Answer…" (the form, in a sheet) and, as on the question card, "Cancel Request" (`question_cancel`).
struct FormWaitingCard: View {
    let card: QuestionCard
    let form: PebbleArtifact
    @Environment(RemoteStore.self) private var store
    /// The screen's opener (`viewOpening()`), so the form's sheet outlives this row in a lazy stack.
    @Environment(ViewOpener.self) private var opener: ViewOpener?
    @State private var isAnswering = false
    @State private var isBusy = false
    @State private var dismissals = 0

    var body: some View {
        PebbleCard(emphasis: .pending) {
            HStack(alignment: .firstTextBaseline) {
                Label(AppCopy.Views.pebblesForm, systemImage: ViewSymbol.kind("form"))
                    .font(PebbleFont.chip)
                    .foregroundStyle(PebbleColor.secondaryText)
                Spacer(minLength: PebbleSpace.s2)
                ToneLabel(AppCopy.Views.waitingForAnswers, tone: .open)
            }
            Text(verbatim: form.title ?? AppCopy.Views.untitledView)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
            if let description = form.form?.description {
                Text(verbatim: description)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
                    .lineLimit(4)
            }
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                ForEach(form.form?.fields ?? []) { field in
                    Text(verbatim: field.label)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(PebbleColor.text)
                        .lineLimit(2)
                }
            }
            Text(card.required ? AppCopy.Reviews.answerRequired : AppCopy.Reviews.answerOptional)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
            HStack(spacing: PebbleSpace.s3) {
                if store.bridgeOffers("artifact_submit") {
                    Button(AppCopy.Views.answerForm, action: answer)
                        .buttonStyle(.pebblePrimary)
                        .accessibilityHint(AppCopy.Views.answerFormHint)
                }
                if store.bridgeOffers("question_cancel") {
                    Button(card.required ? AppCopy.Reviews.cancelRequest : AppCopy.Reviews.skip, action: cancel)
                        .buttonStyle(.pebbleSecondary)
                        .disabled(isBusy)
                }
            }
        }
        .sheet(isPresented: $isAnswering) {
            FormSheet(artifact: form)
                .lockCover()
        }
        .sensoryFeedback(PebbleHaptics.rejected, trigger: dismissals)
    }

    private func answer() {
        if let opener {
            opener.open(form)
        } else {
            isAnswering = true
        }
    }

    private func cancel() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            if await store.attempt({ try await store.dismiss(card) }) { dismissals += 1 }
            isBusy = false
        }
    }
}

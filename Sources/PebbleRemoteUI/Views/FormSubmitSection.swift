import PebbleDesign
import SwiftUI

/// "Submit answers", on while every field is answered. The button keeps Pebble's words: a view's own strings never
/// become a button's label (pebble-ui-spec v1, rule 3), so a form's `submit_label` isn't used here. Under it, a refusal
/// in Pebble's words, and what answering does.
struct FormSubmitSection: View {
    let isBusy: Bool
    let isComplete: Bool
    let failure: String?
    let submit: () -> Void

    var body: some View {
        Section {
            Button(action: submit) {
                HStack {
                    Text(isBusy ? AppCopy.Views.saving : AppCopy.Views.submitAnswers)
                    Spacer(minLength: PebbleSpace.s2)
                    if isBusy {
                        ProgressView()
                    }
                }
                .frame(minHeight: PebbleSize.minTap)
                .contentShape(.rect)
            }
            .disabled(isBusy || !isComplete)
        } footer: {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                if let failure {
                    Text(verbatim: failure)
                        .foregroundStyle(PebbleColor.danger)
                }
                Text(AppCopy.Views.answersBecomeInput)
            }
        }
    }
}

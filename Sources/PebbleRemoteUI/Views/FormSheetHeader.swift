import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The top of a form's sheet: what it is, whether it waits, the model's description (literal), and why a form that
/// no longer waits takes no answers (NativeArtifactRenderer.vue's notes).
struct FormSheetHeader: View {
    let artifact: PebbleArtifact

    var body: some View {
        let state = FormAnswers.state(artifact)
        Section {
            HStack(alignment: .firstTextBaseline) {
                Label(AppCopy.Views.pebblesForm, systemImage: ViewSymbol.kind("form"))
                    .font(PebbleFont.chip)
                    .foregroundStyle(PebbleColor.secondaryText)
                Spacer(minLength: PebbleSpace.s2)
                ToneLabel(state.words, tone: state.tone)
            }
            if let description = artifact.form?.description {
                Text(verbatim: description)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
            }
            if let note = FormAnswers.closedNote(artifact) {
                Text(note)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
    }
}

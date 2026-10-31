import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A plan Pebble drew (NativeArtifactRenderer.vue): each step's title (literal), its state in words with its mark, and
/// the steps of the task its evidence came from.
struct PlanBody: View {
    let plan: NativeView.Plan

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            ForEach(plan.steps) { step in
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Label {
                        Text(verbatim: step.title)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.text)
                    } icon: {
                        Image(systemName: ViewSymbol.step(step.status))
                            .foregroundStyle(step.status == .inProgress ? PebbleColor.accent : step.status.tone.color)
                            .accessibilityHidden(true)
                    }
                    ToneLabel(AppCopy.Views.planStatus(step.status), tone: step.status.tone, showsMark: false)
                        .padding(.leading, PebbleSpace.s6)
                    if !step.evidenceIDs.isEmpty {
                        Text(verbatim: "\(AppCopy.Views.citedStep): \(step.evidenceIDs.joined(separator: ", "))")
                            .font(PebbleFont.meta.monospaced())
                            .foregroundStyle(PebbleColor.mutedText)
                            .padding(.leading, PebbleSpace.s6)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

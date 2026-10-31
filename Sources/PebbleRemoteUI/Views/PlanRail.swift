import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The plan's steps from UpdatePlan (WorkView.vue's rail), the model's titles shown literally, each with its mark and
/// its state in words.
struct PlanRail: View {
    let steps: [WorkPlan.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                Label {
                    Text(verbatim: step.title ?? AppCopy.Views.untitledStep)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(step.status == .completed ? PebbleColor.secondaryText : PebbleColor.text)
                } icon: {
                    Image(systemName: ViewSymbol.step(step.status))
                        .foregroundStyle(step.status == .inProgress ? PebbleColor.accent : step.status.tone.color)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(AppCopy.Views.planStatus(step.status))
            }
        }
    }
}

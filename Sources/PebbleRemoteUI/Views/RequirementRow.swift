import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One requirement of the request, in plain words (literal), with its mark and its state read out.
struct RequirementRow: View {
    let requirement: WorkView.Checks.Requirement

    var body: some View {
        let met = requirement.state == .met
        Label {
            Text(verbatim: requirement.text)
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.text)
        } icon: {
            Image(systemName: met ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(met ? WorkTone.good.color : WorkTone.open.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(met ? AppCopy.Views.met : AppCopy.Views.notConfirmedYet)
    }
}

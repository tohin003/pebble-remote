import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A step whose view this version can't draw (pebble-ui-spec v1, rule 1): its own words, as Pebble showed every step
/// before 1.9.29, and "Update the app to see this view".
struct UnreadableActivityLine: View {
    let text: String
    let status: StatusKey

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            ActivityLine(text: text, status: status)
            Label(AppCopy.Views.updateTheApp, systemImage: ViewSymbol.update)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

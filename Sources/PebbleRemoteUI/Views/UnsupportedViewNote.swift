import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A view this version can't draw (pebble-ui-spec v1, rule 1): its title and kind, and "Update the app to see this
/// view". Never a blank.
struct UnsupportedViewNote: View {
    let artifact: PebbleArtifact

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(verbatim: artifact.title ?? AppCopy.Views.untitledView)
                    .font(PebbleFont.cardTitle)
                    .foregroundStyle(PebbleColor.text)
                Text(AppCopy.Views.updateTheApp)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        } icon: {
            Image(systemName: ViewSymbol.update)
                .foregroundStyle(PebbleColor.secondaryText)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

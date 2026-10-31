import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A page Pebble drew as html: the spec keeps it on the Mac (`x-pebble-surfaces: ["mac"]`), and the phone never draws
/// HTML a model wrote. An honest "Open on Your Mac" row instead.
struct MacOnlyBody: View {
    let artifact: PebbleArtifact

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            Label(AppCopy.Views.kind(artifact.kind), systemImage: ViewSymbol.kind(artifact.kind))
                .font(PebbleFont.chip)
                .foregroundStyle(PebbleColor.secondaryText)
            OnYourMacNote(title: AppCopy.Views.onYourMac, note: AppCopy.Views.pageOnMacNote)
        }
    }
}

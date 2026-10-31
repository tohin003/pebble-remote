import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A view's kind and version (ArtifactPanel.vue's "Version N"), and its state when it no longer changes.
struct ViewScreenHeader: View {
    let artifact: PebbleArtifact
    /// Lane T: an earlier revision shows, which Pebble's header calls "Earlier version N".
    var isEarlier = false

    var body: some View {
        let state = ViewCard.state(artifact)
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
            Label(AppCopy.Views.kind(artifact.kind), systemImage: ViewSymbol.kind(artifact.kind))
                .font(PebbleFont.chip)
                .foregroundStyle(PebbleColor.secondaryText)
            Text(
                isEarlier
                    ? AppCopy.ViewHistory.earlierVersion(artifact.revision) : AppCopy.Views.version(artifact.revision))
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
            Spacer(minLength: PebbleSpace.s2)
            if let state {
                ToneLabel(state.words, tone: state.tone)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

import PebbleDesign
import SwiftUI

/// The pairing screen's top: Pebble's mark, the title, and what to do on the Mac.
struct PairingHeader: View {
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize = 96

    var body: some View {
        VStack {
            PebbleAvatar(pose: .idle)
                .frame(width: avatarSize, height: avatarSize)
                .padding(.vertical)
            Text(AppCopy.Pairing.title)
                .font(.largeTitle)
                .bold()
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(AppCopy.Pairing.intro)
                .font(.body)
                .multilineTextAlignment(.center)
            Text(AppCopy.Pairing.howTo)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom)
    }
}

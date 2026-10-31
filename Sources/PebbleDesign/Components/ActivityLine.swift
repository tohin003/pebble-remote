import PebbleProtocol
import SwiftUI

/// One line of what Pebble did, under the reply it led to: "Edited App.vue", "Ran npm test". The text is Pebble's
/// own step label, shown literally (paths are allowed here, never in a status word); the symbol is the step's kind.
/// Quiet by design: secondary text, small symbol, no background.
public struct ActivityLine: View {
    let text: String
    let status: StatusKey

    public init(text: String, status: StatusKey) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        Label {
            Text(verbatim: text)
                .foregroundStyle(StatusCopy.tone(of: status) == .problem ? PebbleColor.danger : PebbleColor.secondaryText)
                .lineLimit(3)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: PebbleSymbol.status(status))
                .imageScale(.small)
                .foregroundStyle(PebbleColor.mutedText)
                .accessibilityHidden(true)
        }
        .labelStyle(ActivityLineStyle())
        .font(PebbleFont.activity)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityLineStyle: LabelStyle {
    @ScaledMetric(relativeTo: .footnote) private var iconWidth: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
            configuration.icon
                .frame(width: iconWidth)
            configuration.title
        }
    }
}

#if os(iOS)
#Preview("Activity lines") {
    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
        ActivityLine(text: "Read src/App.vue", status: .reading)
        ActivityLine(text: "Searched for \"login\" in 14 files", status: .searching)
        ActivityLine(text: "Edited src/auth/login.ts", status: .editing)
        ActivityLine(text: "Ran npm test", status: .testing)
        ActivityLine(text: "The command failed", status: .error)
    }
    .padding()
}
#endif

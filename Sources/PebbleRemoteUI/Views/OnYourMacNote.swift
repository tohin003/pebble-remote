import PebbleDesign
import SwiftUI

/// Something only the Mac does (IA rule 6): grey, never a dead button, with the reason under it. (Settings' one-line
/// row is `Control/OnYourMacRow`; a module can't hold two files or two types of one name.)
struct OnYourMacNote: View {
    let title: String
    let note: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(title)
                    .font(PebbleFont.cardTitle)
                    .foregroundStyle(PebbleColor.secondaryText)
                Text(note)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        } icon: {
            Image(systemName: ViewSymbol.onYourMac)
                .foregroundStyle(PebbleColor.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(PebbleSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PebbleColor.soft, in: .rect(cornerRadius: PebbleRadius.md))
        .accessibilityElement(children: .combine)
    }
}

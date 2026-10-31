import PebbleDesign
import SwiftUI

/// Something only Pebble on the Mac can do (docs/parity/IA.md rule 6): a grey row that says "On your Mac", never a dead
/// button; the section's footer says why. It shows that the Mac's section exists, so the person knows where to look.
struct OnYourMacRow: View {
    let title: String

    var body: some View {
        LabeledContent {
            Label(AppCopy.SettingsTab.onYourMac, systemImage: PebbleSymbol.mac)
                .labelStyle(.titleAndIcon)
                .font(PebbleFont.meta)
        } label: {
            Text(title)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

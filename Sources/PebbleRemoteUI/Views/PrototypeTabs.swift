import PebbleDesign
import PebbleProtocol
import SwiftUI

/// An app demo's tab bar: each tab switches to its screen; the current one is marked in words for VoiceOver too.
struct PrototypeTabs: View {
    let links: [NativeView.Prototype.Link]
    let current: String
    let go: (String?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                Button {
                    go(link.target)
                } label: {
                    Text(verbatim: link.label)
                        .font(PebbleFont.chip)
                        .foregroundStyle(link.target == current ? PebbleColor.accent : PebbleColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: PebbleSize.minTap)
                }
                .buttonStyle(.plain)
                .disabled(link.target == nil)
                .accessibilityAddTraits(link.target == current ? .isSelected : [])
            }
        }
        .background(PebbleColor.soft)
    }
}

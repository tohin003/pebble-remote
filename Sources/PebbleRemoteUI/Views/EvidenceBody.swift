import PebbleDesign
import PebbleProtocol
import SwiftUI

/// Evidence Pebble drew (NativeArtifactRenderer.vue): its caption, then each item's label, summary and the step of the
/// task it cites. Pebble's window calls that a "Tool receipt"; the phone names it plainly.
struct EvidenceBody: View {
    let evidence: NativeView.Evidence

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            if let caption = evidence.caption {
                Text(verbatim: caption)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            ForEach(evidence.items) { item in
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Label {
                        Text(verbatim: item.label)
                            .font(PebbleFont.cardTitle)
                            .foregroundStyle(PebbleColor.text)
                    } icon: {
                        Image(systemName: ViewSymbol.kind("evidence"))
                            .foregroundStyle(PebbleColor.ok)
                            .accessibilityHidden(true)
                    }
                    if let summary = item.summary {
                        Text(verbatim: summary)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.text)
                    }
                    Text(verbatim: "\(AppCopy.Views.citedStep): \(item.evidenceID)")
                        .font(PebbleFont.meta.monospaced())
                        .foregroundStyle(PebbleColor.mutedText)
                        .textSelection(.enabled)
                }
                .padding(PebbleSpace.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.md))
                .overlay { RoundedRectangle(cornerRadius: PebbleRadius.md).stroke(PebbleColor.line, lineWidth: 1) }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

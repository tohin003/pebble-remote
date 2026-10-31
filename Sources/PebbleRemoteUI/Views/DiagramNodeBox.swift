import PebbleDesign
import SwiftUI

/// One diagram node: its label in a box with a hairline.
struct DiagramNodeBox: View {
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(PebbleFont.cardBody)
            .foregroundStyle(PebbleColor.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, PebbleSpace.s3)
            .padding(.vertical, PebbleSpace.s2)
            .frame(maxWidth: 220)
            .background(PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.sm))
            .overlay { RoundedRectangle(cornerRadius: PebbleRadius.sm).stroke(PebbleColor.lineStrong, lineWidth: 1) }
    }
}

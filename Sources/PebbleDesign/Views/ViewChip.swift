import SwiftUI

/// A chip of display text (a path, a query, a site), shown literally, with an optional quiet note ("212 lines").
public struct ViewChip: View {
    let text: String
    let note: String?
    let monospaced: Bool

    public init(_ text: String, note: String? = nil, monospaced: Bool = false) {
        self.text = text
        self.note = note
        self.monospaced = monospaced
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s1) {
            Text(verbatim: text)
                .font(monospaced ? PebbleFont.chip.monospaced() : PebbleFont.chip)
                .foregroundStyle(PebbleColor.text)
                .lineLimit(1)
                .truncationMode(.middle)
            if let note {
                Text(note)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, PebbleSpace.s2)
        .padding(.vertical, PebbleSpace.s1)
        .background(PebbleColor.soft, in: .capsule)
        .overlay { Capsule().stroke(PebbleColor.line, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

import PebbleProtocol
import SwiftUI

/// A state in words, with its mark and its colour beside them (spec rule 5): "Done" in green, "Failed" in red,
/// "Waiting for you" in amber. The words always carry the meaning; the colour and the mark only repeat it.
public struct ToneLabel: View {
    let text: String
    let tone: WorkTone
    let showsMark: Bool

    public init(_ text: String, tone: WorkTone, showsMark: Bool = true) {
        self.text = text
        self.tone = tone
        self.showsMark = showsMark
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s1) {
            if showsMark {
                Image(systemName: ViewSymbol.tone(tone))
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(PebbleFont.chip)
        .foregroundStyle(tone.color)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

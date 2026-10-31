import PebbleDesign
import SwiftUI

/// One choice of a question (QuizRenderer.vue's radio buttons): its letter, A to F, and its words (literal), the whole
/// row one target of at least 44 pt. The chosen one shows by its border, its filled letter and VoiceOver's "selected",
/// never by colour alone; while choices are closed (time is up, or Pebble is checking) the rows dim.
struct QuizChoiceRow: View {
    let letter: String
    let words: String
    let isChosen: Bool
    let isEnabled: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s3) {
                Text(letter)
                    .font(PebbleFont.chip.monospaced())
                    .foregroundStyle(isChosen ? PebbleColor.onAccent : PebbleColor.secondaryText)
                    .padding(.horizontal, PebbleSpace.s2)
                    .padding(.vertical, PebbleSpace.s1 / 2)
                    .background(isChosen ? PebbleColor.accent : Color.clear, in: .rect(cornerRadius: PebbleRadius.sm))
                    .overlay {
                        RoundedRectangle(cornerRadius: PebbleRadius.sm)
                            .stroke(isChosen ? PebbleColor.accent : PebbleColor.lineStrong, lineWidth: 1)
                    }
                Text(verbatim: words)
                    .font(PebbleFont.message)
                    .foregroundStyle(PebbleColor.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(PebbleSpace.s3)
            .frame(maxWidth: .infinity, minHeight: PebbleSize.minTap, alignment: .leading)
            .background(isChosen ? PebbleColor.soft : PebbleColor.panel, in: .rect(cornerRadius: PebbleRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: PebbleRadius.md)
                    .stroke(isChosen ? PebbleColor.accent : PebbleColor.line, lineWidth: isChosen ? 2 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

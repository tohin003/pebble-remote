import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A terminal command (WorkCard.vue): where it ran and whether it could reach the network, the whole command, and the
/// last lines of its output, all literal (Pebble masks secrets before they leave the Mac).
struct CommandDetails: View {
    let command: WorkView.Command

    var body: some View {
        let place = [
            command.place, command.usesNetwork.map { $0 ? AppCopy.Views.withNetwork : AppCopy.Views.noNetwork },
        ].compactMap { $0 }.joined(separator: " \u{00B7} ")
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if !place.isEmpty {
                Text(verbatim: place)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            if let line = command.command {
                Text(verbatim: line)
                    .font(PebbleFont.cardDetail)
                    .foregroundStyle(PebbleColor.text)
                    .textSelection(.enabled)
            }
            if !command.tail.isEmpty {
                Text(verbatim: command.tail.joined(separator: "\n"))
                    .font(PebbleFont.code)
                    .foregroundStyle(PebbleColor.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PebbleSpace.s2)
                    .background(PebbleColor.code, in: .rect(cornerRadius: PebbleRadius.sm))
                    .accessibilityLabel(AppCopy.Views.lastLines)
                    .accessibilityValue(command.tail.joined(separator: ", "))
            }
            if command.isCut {
                Text(AppCopy.Views.outputWasLonger)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
    }
}

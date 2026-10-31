import PebbleDesign
import PebbleProtocol
import SwiftUI

/// One look or press in a window: "Pressed “=”", "12*7 → 84", and its verdict in words.
struct WindowStepRow: View {
    let window: WorkView.Window

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(verbatim: Self.action(window))
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.text)
            if window.before != nil || window.after != nil {
                Text(verbatim: "\(window.before ?? "") \u{2192} \(window.after ?? "")")
                    .font(PebbleFont.cardDetail)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            if let verdict = window.verdict {
                ToneLabel(AppCopy.Views.verdict(verdict), tone: verdict == .happened ? .good : .open)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The verb and its target, as Pebble words them: `Pressed “=”`.
    static func action(_ window: WorkView.Window) -> String {
        [window.verb, window.target.map { "\u{201C}\($0)\u{201D}" }].compactMap { $0 }.joined(separator: " ")
    }
}

import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A settled run's summary as chips (workView.ts `summaryWords`): files changed, commands, tests, the check's verdict
/// and the tokens. The time is left out: where these show, the line above already says how long the run took.
struct WorkSummaryChips: View {
    let summary: WorkSummary

    var body: some View {
        let chips = Self.words(summary)
        if !chips.isEmpty {
            ChipFlow(spacing: PebbleSpace.s1) {
                ForEach(chips, id: \.self) { chip in
                    ViewChip(chip)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(AppCopy.Views.summary)
            .accessibilityValue(chips.joined(separator: ", "))
        }
    }

    static func words(_ summary: WorkSummary) -> [String] {
        var shown = summary
        shown.seconds = nil
        return AppCopy.Views.summaryChips(shown)
    }
}

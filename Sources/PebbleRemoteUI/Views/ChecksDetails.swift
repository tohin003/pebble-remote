import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The completion check (WorkCard.vue): its verdict, its test run, and what the request requires, each met or not
/// confirmed yet in words. Pebble's records count the issues, not which requirement each belongs to, so no single
/// requirement is called unmet; the reply says which.
struct ChecksDetails: View {
    let checks: WorkView.Checks

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if let verdict = checks.verdict {
                ToneLabel(verdict, tone: verdict.hasPrefix("Verified") ? .good : .open)
            }
            if let tests = checks.tests {
                Text(
                    AppCopy.Views.checkTests(
                        runner: tests.runner, passed: tests.passed ?? 0, failed: tests.failed ?? 0, current: tests.isCurrent)
                )
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
            }
            ForEach(Array(checks.requirements.enumerated()), id: \.offset) { _, requirement in
                RequirementRow(requirement: requirement)
            }
            if checks.wasRepaired {
                Text(AppCopy.Views.metAfterRepair)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            if let unmet = checks.unmet, unmet > 0 {
                ToneLabel(AppCopy.Views.notMetYet(unmet), tone: .open, showsMark: false)
            }
        }
    }
}

import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A test run (WorkCard.vue): its counts and time, a bar of passed, failed and skipped, and the failing tests' names
/// (display only).
struct TestsDetails: View {
    let tests: WorkView.Tests

    var body: some View {
        let counts = AppCopy.Views.testCounts(
            passed: tests.passed ?? 0, failed: tests.failed ?? 0, skipped: tests.skipped ?? 0, errors: tests.errors ?? 0)
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Text([counts, RunCopy.formatDuration(tests.seconds)].compactMap { $0 }.joined(separator: " \u{00B7} "))
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.text)
            TestMeter(
                passed: tests.passed ?? 0, failed: (tests.failed ?? 0) + (tests.errors ?? 0), skipped: tests.skipped ?? 0,
                words: counts)
            if !tests.failing.isEmpty {
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Text(AppCopy.Views.failingTests)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                    ForEach(tests.failing, id: \.self) { name in
                        Text(verbatim: name)
                            .font(PebbleFont.cardDetail)
                            .foregroundStyle(PebbleColor.danger)
                            .textSelection(.enabled)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

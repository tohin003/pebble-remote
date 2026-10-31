import PebbleDesign
import SwiftUI

/// A test run's bar: passed in green, failed in red, skipped muted, each as long as its share. Read out as its words.
struct TestMeter: View {
    let passed: Int
    let failed: Int
    let skipped: Int
    let words: String

    var body: some View {
        let all: [(count: Int, color: Color)] = [
            (passed, PebbleColor.ok), (failed, PebbleColor.danger), (skipped, PebbleColor.mutedText),
        ]
        let parts = all.filter { $0.count > 0 }
        let total = max(1, parts.reduce(0) { $0 + $1.count })
        if !parts.isEmpty {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(part.color)
                            .frame(width: max(2, (proxy.size.width - CGFloat(parts.count - 1) * 2) * CGFloat(part.count) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel(words)
        }
    }
}

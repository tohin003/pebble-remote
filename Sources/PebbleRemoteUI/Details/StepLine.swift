import PebbleDesign
import SwiftUI

/// A step's name and its time from the run's start, never running into each other (UX audit U-46): side by side with a
/// fixed gap, the time always at its whole width and the name wrapping before it; stacked at accessibility text sizes,
/// where a row has no room for both.
struct StepLine: View {
    let name: String
    let time: String?
    var nameFont: Font = PebbleFont.cardBody
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Arrangement: Equatable {
        case sideBySide, stacked
    }

    static func arrangement(for size: DynamicTypeSize) -> Arrangement {
        size.isAccessibilitySize ? .stacked : .sideBySide
    }

    /// The gap between the name and the time when they share a line.
    static let gap = PebbleSpace.s3

    var body: some View {
        let layout =
            Self.arrangement(for: typeSize) == .stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PebbleSpace.s1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Self.gap))
        layout {
            Text(verbatim: name)
                .font(nameFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let time {
                Text(verbatim: time)
                    .font(PebbleFont.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
}

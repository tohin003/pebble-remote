import PebbleDesign
import SwiftUI

/// A file's change as two bars, added in green and removed in red, scaled to the card's largest change; its words
/// are read out (WorkCard.vue's `file-bar`).
struct DiffBar: View {
    let added: Int
    let removed: Int
    let widest: Int
    @ScaledMetric(relativeTo: .footnote) private var length: CGFloat = 64

    var body: some View {
        HStack(spacing: 2) {
            Capsule().fill(PebbleColor.ok).frame(width: width(added))
            Capsule().fill(PebbleColor.danger).frame(width: width(removed))
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel(AppCopy.Views.linesChanged(added: added, removed: removed))
    }

    private func width(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(4, (CGFloat(count) / CGFloat(max(1, widest)) * length).rounded())
    }
}

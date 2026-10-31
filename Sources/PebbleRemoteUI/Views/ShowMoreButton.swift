import PebbleDesign
import SwiftUI

/// "Show N More" past the work view's six chips or rows (pebble-ui-spec v1, rule 5), and "Show Less".
struct ShowMoreButton: View {
    let hidden: Int
    @Binding var showsAll: Bool

    var body: some View {
        Button(showsAll ? AppCopy.Views.showLess : AppCopy.Views.showMore(hidden)) {
            showsAll.toggle()
        }
        .font(PebbleFont.meta)
        .buttonStyle(.borderless)
        .frame(minHeight: PebbleSize.minTap, alignment: .leading)
    }

    /// The work view's budget: six chips or rows before "Show more".
    static let shown = 6
}

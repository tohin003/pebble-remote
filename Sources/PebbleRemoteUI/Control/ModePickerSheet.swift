import PebbleDesign
import SwiftUI

/// The permission modes in a sheet, opened from the mode chip on the overview.
struct ModePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ModePickerList()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppCopy.Common.done) { dismiss() }
                            .pebbleBarButton()
                    }
                }
        }
    }
}

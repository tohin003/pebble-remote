import PebbleDesign
import SwiftUI

/// The Mac screen's toolbar: which display (only when there is more than one), Refresh, and Share.
struct MacScreenToolbar: ToolbarContent {
    let capture: MacScreenCapture?
    @Binding var selected: Int?
    let shown: MacScreenCapture.Display?
    let isLoading: Bool
    let refresh: () -> Void

    var body: some ToolbarContent {
        if let capture, capture.displays.count > 1 {
            ToolbarItem(placement: .primaryAction) {
                Picker(AppCopy.MacScreen.displayPicker, selection: $selected) {
                    ForEach(capture.displays) { display in
                        Text(AppCopy.MacScreen.display(display.index + 1)).tag(Optional(display.index))
                    }
                }
                .pickerStyle(.menu)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(AppCopy.MacScreen.refresh, systemImage: "arrow.clockwise", action: refresh)
                .disabled(isLoading)
        }
        if let shown {
            ToolbarItem(placement: .primaryAction) {
                let picture = Image(decorative: shown.image, scale: 1)
                ShareLink(
                    item: picture,
                    preview: SharePreview(AppCopy.MacScreen.title, image: picture))
            }
        }
    }
}

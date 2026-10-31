import PebbleDesign
import PebbleProtocol
import SwiftUI

/// Looks and presses in an app window (WorkCard.vue): where Pebble pressed, in a neutral frame of the window's size
/// (no route serves the picture in version 1), then each step: what it did, what changed, and whether it happened.
struct WindowDetails: View {
    let windows: [WorkView.Window]
    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if let press = windows.reversed().compactMap(\.pressInFrame).first {
                WindowFrame(
                    width: press.picture.width, height: press.picture.height,
                    point: CGPoint(x: press.point.x, y: press.point.y))
            }
            ForEach(Array(windows.prefix(showsAll ? windows.count : ShowMoreButton.shown).enumerated()), id: \.offset) {
                _, window in
                WindowStepRow(window: window)
            }
            if windows.count > ShowMoreButton.shown {
                ShowMoreButton(hidden: windows.count - ShowMoreButton.shown, showsAll: $showsAll)
            }
        }
    }
}

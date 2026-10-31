import PebbleDesign
import SwiftUI

extension View {
    /// A text button's label with a 44 × 44 pt hit region (Apple's minimum). Put it on the label, inside the button: a
    /// frame outside a borderless button makes room around it but doesn't widen what can be tapped.
    func tapTarget(alignment: Alignment = .center) -> some View {
        frame(minWidth: PebbleSize.minTap, minHeight: PebbleSize.minTap, alignment: alignment)
            .contentShape(.rect)
    }
}

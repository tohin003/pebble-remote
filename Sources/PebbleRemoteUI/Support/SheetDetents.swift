import SwiftUI

extension View {
    /// A form sheet's heights: half the screen where its words fit, and the full screen at accessibility text sizes,
    /// where half a screen would cut them (Dynamic Type; UX audit, the sheets' fixed sizes).
    func formSheetDetents(_ typeSize: DynamicTypeSize) -> some View {
        presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}

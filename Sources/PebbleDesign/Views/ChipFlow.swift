import SwiftUI

/// Views in rows that wrap (`FlowLayout`): chips, summary words, a diagram's level. A layout is called as a function
/// on an instance, so this wraps that call for the screens.
public struct ChipFlow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    public init(spacing: CGFloat = PebbleSpace.s2, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        FlowLayout(spacing: spacing).callAsFunction {
            content
        }
    }
}

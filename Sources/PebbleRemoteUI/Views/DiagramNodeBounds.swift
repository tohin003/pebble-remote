import SwiftUI

/// Where each diagram node sits, by node id, so the edges can be drawn between them.
nonisolated struct DiagramNodeBounds: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

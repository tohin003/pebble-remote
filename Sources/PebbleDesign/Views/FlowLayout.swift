import SwiftUI

/// Lays its children in rows, wrapping to the next row when one is full (chips, summary words).
nonisolated public struct FlowLayout: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat = PebbleSpace.s2) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, width: bounds.width)
        for row in rows {
            for (index, x) in zip(row.indices, row.xs) {
                let size = row.sizes[index - row.indices.lowerBound]
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height))
            }
        }
    }

    private struct Row {
        var indices: Range<Int>
        var xs: [CGFloat]
        var sizes: [CGSize]
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var start = 0
        var xs: [CGFloat] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0, x + size.width > width {
                rows.append(Row(indices: start..<index, xs: xs, sizes: sizes, y: y, width: x - spacing, height: height))
                y += height + spacing
                start = index
                xs = []
                sizes = []
                x = 0
                height = 0
            }
            xs.append(x)
            sizes.append(CGSize(width: min(size.width, width), height: size.height))
            x += min(size.width, width) + spacing
            height = max(height, size.height)
        }
        if start < subviews.count {
            rows.append(Row(indices: start..<subviews.count, xs: xs, sizes: sizes, y: y, width: x - spacing, height: height))
        }
        return rows
    }
}

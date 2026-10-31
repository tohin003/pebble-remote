import PebbleDesign
import PebbleProtocol
import SwiftUI

/// The diagram's edges, behind its nodes: a line with an arrowhead from one box to the other (down a level, across a
/// level, or curving back up for a cycle), and the edge's label at its middle. The words are in "Diagram as text".
struct DiagramEdges: View {
    let edges: [NativeView.Diagram.Edge]
    let frames: [String: CGRect]

    var body: some View {
        let routes = edges.compactMap { edge in Self.route(edge, frames: frames).map { (edge, $0) } }
        ZStack(alignment: .topLeading) {
            Path { path in
                for (_, route) in routes {
                    path.move(to: route.start)
                    path.addQuadCurve(to: route.end, control: route.control)
                }
            }
            .stroke(PebbleColor.lineStrong, lineWidth: 1.5)
            Path { path in
                for (_, route) in routes {
                    path.addLines(Self.arrowhead(at: route.end, from: route.control))
                    path.closeSubpath()
                }
            }
            .fill(PebbleColor.lineStrong)
            ForEach(Array(routes.enumerated()), id: \.offset) { _, pair in
                if let label = pair.0.label {
                    Text(verbatim: label)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                        .padding(.horizontal, PebbleSpace.s1)
                        .background(PebbleColor.bg.opacity(0.9), in: .rect(cornerRadius: 4))
                        .fixedSize()
                        .position(pair.1.middle)
                }
            }
        }
        .accessibilityHidden(true)
    }

    struct Route {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        /// Halfway along the curve.
        var middle: CGPoint {
            CGPoint(
                x: 0.25 * start.x + 0.5 * control.x + 0.25 * end.x, y: 0.25 * start.y + 0.5 * control.y + 0.25 * end.y)
        }
    }

    static func route(_ edge: NativeView.Diagram.Edge, frames: [String: CGRect]) -> Route? {
        guard let from = frames[edge.from], let to = frames[edge.to], edge.from != edge.to else { return nil }
        if to.minY >= from.maxY {
            let start = CGPoint(x: from.midX, y: from.maxY)
            let end = CGPoint(x: to.midX, y: to.minY)
            return Route(start: start, control: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), end: end)
        }
        if abs(to.midY - from.midY) < 1 {
            let rightward = to.midX > from.midX
            let start = CGPoint(x: rightward ? from.maxX : from.minX, y: from.midY)
            let end = CGPoint(x: rightward ? to.minX : to.maxX, y: to.midY)
            return Route(start: start, control: CGPoint(x: (start.x + end.x) / 2, y: from.minY - 16), end: end)
        }
        // Back up to an earlier level: out of the box's side, curving wide.
        let start = CGPoint(x: from.maxX, y: from.midY)
        let end = CGPoint(x: to.maxX, y: to.midY)
        return Route(start: start, control: CGPoint(x: max(start.x, end.x) + 48, y: (start.y + end.y) / 2), end: end)
    }

    /// A small arrowhead at `tip`, pointing away from `from`.
    static func arrowhead(at tip: CGPoint, from: CGPoint) -> [CGPoint] {
        let dx = tip.x - from.x, dy = tip.y - from.y
        let length = max(0.001, (dx * dx + dy * dy).squareRoot())
        let ux = dx / length, uy = dy / length
        let back = CGPoint(x: tip.x - ux * 8, y: tip.y - uy * 8)
        return [tip, CGPoint(x: back.x - uy * 4, y: back.y + ux * 4), CGPoint(x: back.x + uy * 4, y: back.y - ux * 4)]
    }
}

import PebbleDesign
import PebbleProtocol

/// A diagram's nodes in levels, top to bottom (a layered layout, as diagramLayout.ts lays out Pebble's): the nodes no
/// edge points to first, then each node one level below the first node that points to it. Nodes only a cycle reaches
/// start a new level after the deepest one. The model's order is kept within a level.
enum DiagramLevels {
    static func levels(_ diagram: NativeView.Diagram) -> [[NativeView.Diagram.Node]] {
        let pointedTo = Set(diagram.edges.map(\.to))
        var level: [String: Int] = [:]
        var queue: [String] = []
        func visit(from start: [String], at depth: Int) {
            queue = start
            for id in start where level[id] == nil { level[id] = depth }
            var index = 0
            while index < queue.count {
                let id = queue[index]
                index += 1
                for edge in diagram.edges where edge.from == id && level[edge.to] == nil {
                    level[edge.to] = (level[id] ?? depth) + 1
                    queue.append(edge.to)
                }
            }
        }
        visit(from: diagram.nodes.map(\.id).filter { !pointedTo.contains($0) }, at: 0)
        while let next = diagram.nodes.first(where: { level[$0.id] == nil }) {
            visit(from: [next.id], at: (level.values.max() ?? -1) + 1)
        }
        let deepest = level.values.max() ?? 0
        return (0...max(0, deepest)).map { depth in diagram.nodes.filter { level[$0.id] == depth } }.filter { !$0.isEmpty }
    }

    /// The diagram in words, one relation a line: "Request → Auth middleware: checks session".
    static func lines(_ diagram: NativeView.Diagram) -> [String] {
        let names = Dictionary(diagram.nodes.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        return diagram.edges.map { edge in
            AppCopy.Views.edge(from: names[edge.from] ?? edge.from, to: names[edge.to] ?? edge.to, label: edge.label)
        }
    }
}

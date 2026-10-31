import PebbleDesign
import PebbleProtocol
import SwiftUI

/// A diagram Pebble drew (VisualDiagram.vue): its nodes in levels, top to bottom, with each labelled edge drawn
/// between them, and "Diagram as text" with every relation in words. Every label is the model's: shown literally.
struct DiagramBody: View {
    let diagram: NativeView.Diagram
    @State private var showsText = false

    var body: some View {
        let levels = DiagramLevels.levels(diagram)
        VStack(alignment: .leading, spacing: PebbleSpace.s4) {
            VStack(alignment: .leading, spacing: PebbleSpace.s6) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, nodes in
                    ChipFlow(spacing: PebbleSpace.s3) {
                        ForEach(nodes) { node in
                            DiagramNodeBox(label: node.label)
                                .anchorPreference(key: DiagramNodeBounds.self, value: .bounds) { [node.id: $0] }
                        }
                    }
                }
            }
            .padding(.vertical, PebbleSpace.s2)
            .backgroundPreferenceValue(DiagramNodeBounds.self) { anchors in
                GeometryReader { proxy in
                    DiagramEdges(edges: diagram.edges, frames: anchors.mapValues { proxy[$0] })
                }
            }
            DisclosureGroup(AppCopy.Views.diagramAsText, isExpanded: $showsText) {
                VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                    ForEach(Array(DiagramLevels.lines(diagram).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.text)
                    }
                }
                .padding(.top, PebbleSpace.s2)
            }
            .font(PebbleFont.cardBody)
        }
    }
}

import SwiftUI

/// Shapes with Pebble's radii on iOS 26's geometry.
nonisolated public enum PebbleShapes {
    /// A card: concentric with its container (a screen or sheet edge) when it sits near one, else Pebble's 18 pt.
    public static let card = ConcentricRectangle(corners: .concentric(minimum: .fixed(PebbleRadius.lg)), isUniform: true)
    /// A fill inside a card (code, the exact detail): concentric with the card, at least 8 pt.
    public static let inset = ConcentricRectangle(corners: .concentric(minimum: .fixed(PebbleRadius.sm)), isUniform: true)
    /// Your message bubble: Pebble's 13/13/3/13 px corners, the small one at the trailing bottom.
    public static let personBubble = UnevenRoundedRectangle(
        topLeadingRadius: PebbleRadius.bubble, bottomLeadingRadius: PebbleRadius.bubble,
        bottomTrailingRadius: PebbleRadius.bubbleTail, topTrailingRadius: PebbleRadius.bubble)
}

/// A card in the content layer: Pebble's panel colour, a hairline, Pebble's radius. Never glass: cards are content.
/// `.pending` marks something waiting for the person (Pebble's `.action-card.pending`: the soft accent border).
public struct PebbleCard<Content: View>: View {
    public enum Emphasis: Sendable { case plain, pending, problem }

    let emphasis: Emphasis
    let content: Content

    public init(emphasis: Emphasis = .plain, @ViewBuilder content: () -> Content) {
        self.emphasis = emphasis
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            content
        }
        .padding(PebbleSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerShape(.rect(cornerRadius: PebbleRadius.lg))
        .background(PebbleColor.panel, in: PebbleShapes.card)
        .overlay {
            PebbleShapes.card.stroke(border, lineWidth: emphasis == .plain ? 1 : 1.5)
        }
    }

    private var border: Color {
        switch emphasis {
        case .plain: PebbleColor.line
        case .pending: PebbleColor.accentSoft
        case .problem: PebbleColor.dangerLine
        }
    }
}

#if os(iOS)
#Preview("Cards") {
    ScrollView {
        VStack(spacing: PebbleSpace.s3) {
            PebbleCard {
                Text("A plain card").font(PebbleFont.cardTitle).foregroundStyle(PebbleColor.text)
                Text("Content lives on Pebble's panel colour, never on glass.")
                    .font(PebbleFont.cardBody).foregroundStyle(PebbleColor.secondaryText)
            }
            PebbleCard(emphasis: .pending) {
                Text(AppCopy.Reviews.needsYourReview).font(PebbleFont.cardTitle).foregroundStyle(PebbleColor.text)
            }
            PebbleCard(emphasis: .problem) {
                Text(StatusCopy.word(for: .error)).font(PebbleFont.cardTitle).foregroundStyle(PebbleColor.danger)
            }
        }
        .padding()
    }
    .background(Color(uiColor: .systemGroupedBackground))
}
#endif

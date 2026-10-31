import PebbleDesign
import SwiftUI

/// Where Pebble pressed, as a mark in a neutral frame with the window picture's proportions (WorkCard.vue's `frame`):
/// the picture stays on the Mac.
struct WindowFrame: View {
    let width: Int
    let height: Int
    let point: CGPoint

    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.stroke(Path(roundedRect: frame, cornerRadius: 6), with: .color(PebbleColor.lineStrong), lineWidth: 1)
            let scale = size.width / CGFloat(max(1, width))
            let center = CGPoint(x: point.x * scale, y: point.y * scale)
            let radius = max(6, min(size.width, size.height) / 18)
            let mark = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(mark, with: .color(PebbleColor.accent.opacity(0.3)))
            context.stroke(mark, with: .color(PebbleColor.accent), lineWidth: 2)
        }
        .aspectRatio(CGFloat(max(1, width)) / CGFloat(max(1, height)), contentMode: .fit)
        .frame(maxWidth: 240, maxHeight: 180, alignment: .leading)
        .accessibilityElement()
        .accessibilityLabel(AppCopy.Views.wherePebblePressed)
    }
}

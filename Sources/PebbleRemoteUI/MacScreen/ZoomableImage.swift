import CoreGraphics
import SwiftUI

/// An image that fits the space and zooms: pinch, or double-tap to switch between fitted and 2.5×; pan by scrolling
/// when zoomed. VoiceOver's zoom gesture works too. Under Reduce Motion the zoom changes without animating.
struct ZoomableImage: View {
    let image: CGImage
    let label: String
    @State private var scale = 1.0
    @GestureState private var pinch = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let range = 1.0...6.0

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedSize(in: proxy.size)
            let zoom = clamped(scale * pinch)
            ScrollView([.horizontal, .vertical]) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fitted.width * zoom, height: fitted.height * zoom)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollIndicators(zoom > 1 ? .automatic : .hidden)
            .scrollDisabled(zoom <= 1)
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = clamped(scale * value.magnification) }
            )
            .onTapGesture(count: 2) { toggleZoom() }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
        .accessibilityZoomAction { action in
            switch action.direction {
            case .zoomIn: setZoom(clamped(scale * 1.5))
            case .zoomOut: setZoom(clamped(scale / 1.5))
            @unknown default: break
            }
        }
    }

    /// The image's size when it fits the space, keeping its aspect ratio.
    private func fittedSize(in space: CGSize) -> CGSize {
        let width = Double(image.width), height = Double(image.height)
        guard width > 0, height > 0, space.width > 0, space.height > 0 else { return .zero }
        let ratio = min(space.width / width, space.height / height)
        return CGSize(width: width * ratio, height: height * ratio)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, Self.range.lowerBound), Self.range.upperBound)
    }

    private func toggleZoom() {
        setZoom(scale > 1 ? 1 : 2.5)
    }

    private func setZoom(_ value: Double) {
        if reduceMotion {
            scale = value
        } else {
            withAnimation(.snappy) { scale = value }
        }
    }
}

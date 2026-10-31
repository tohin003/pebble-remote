import CoreGraphics
import SwiftUI

/// Your Mac's screen (claude-w's C3, `remote.screenshot`): the picture full width, pinch or double-tap to zoom, a
/// display picker when the Mac has several, when it was taken, and what happens to it (the Mac keeps no copy and shows
/// a notice; this iPhone keeps it only if you share it). Before the first picture, an empty state with Take Screenshot.
/// It adds Share and Take Another to the enclosing navigation bar.
///
/// The screen decodes the bridge's JPEG into a `CGImage` (ImageIO) and passes the displays in.
public struct ScreenshotView: View {
    public struct Display: Identifiable, Hashable, @unchecked Sendable {
        public var index: Int
        public var image: CGImage
        public var id: Int { index }
        public init(index: Int, image: CGImage) {
            self.index = index
            self.image = image
        }
    }

    let displays: [Display]
    let takenAt: Date?
    let isTaking: Bool
    let stealth: Bool
    let onTake: () -> Void

    @State private var selected = 0

    /// - Parameters:
    ///   - stealth: Stealth Lockdown is on (Pebble's own windows stay out of the picture; said under it).
    public init(displays: [Display], takenAt: Date?, isTaking: Bool, stealth: Bool, onTake: @escaping () -> Void) {
        self.displays = displays
        self.takenAt = takenAt
        self.isTaking = isTaking
        self.stealth = stealth
        self.onTake = onTake
    }

    private var current: Display? { displays.first { $0.index == selected } ?? displays.first }

    public var body: some View {
        VStack(spacing: PebbleSpace.s3) {
            if let current {
                if displays.count > 1 {
                    Picker(SettingsCopy.Screenshot.displays, selection: $selected) {
                        ForEach(displays) { Text(SettingsCopy.Screenshot.display($0.index)).tag($0.index) }
                    }
                    .pickerStyle(.segmented)
                }
                ZoomableScreenshot(
                    image: current.image,
                    label: takenAt.map { SettingsCopy.Screenshot.imageLabel(display: current.index, taken: $0) }
                        ?? SettingsCopy.Screenshot.display(current.index))
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    if let takenAt {
                        Text(SettingsCopy.Screenshot.taken(takenAt))
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.secondaryText)
                    }
                    Text(verbatim: SettingsCopy.Screenshot.note)
                    if stealth { Text(verbatim: SettingsCopy.Screenshot.stealthNote) }
                }
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView {
                    Label(SettingsCopy.Screenshot.title, systemImage: PebbleSymbol.screenshot)
                } description: {
                    Text(verbatim: SettingsCopy.Screenshot.note + (stealth ? " " + SettingsCopy.Screenshot.stealthNote : ""))
                } actions: {
                    Button(SettingsCopy.Screenshot.take, systemImage: PebbleSymbol.screenshot, action: onTake)
                        .buttonStyle(.pebblePrimary)
                        .disabled(isTaking)
                }
            }
        }
        .overlay {
            if isTaking {
                ProgressView(SettingsCopy.Screenshot.taking)
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: PebbleRadius.md))
            }
        }
        .toolbar {
            if let current {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: Image(decorative: current.image, scale: 1),
                        preview: SharePreview(SettingsCopy.Screenshot.title, image: Image(decorative: current.image, scale: 1))
                    ) {
                        Label(SettingsCopy.Screenshot.share, systemImage: PebbleSymbol.share)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(SettingsCopy.Screenshot.takeAgain, systemImage: PebbleSymbol.screenshot, action: onTake)
                        .disabled(isTaking)
                }
            }
        }
    }
}

/// The picture: fits the width; pinch to zoom up to 6x, drag while zoomed, double-tap to switch between fit and 2.5x.
/// VoiceOver can zoom with its own zoom action.
private struct ZoomableScreenshot: View {
    let image: CGImage
    let label: String

    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: PebbleRadius.md))
            .contentShape(.rect)
            .gesture(magnify.simultaneously(with: pan))
            .onTapGesture(count: 2, perform: toggleZoom)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isImage)
            .accessibilityHint(SettingsCopy.Screenshot.zoomHint)
            .accessibilityZoomAction { action in
                setScale(action.direction == .zoomIn ? min(scale * 1.5, 6) : max(scale / 1.5, 1))
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(settledScale * value.magnification, 1), 6) }
            .onEnded { _ in setScale(scale) }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: settledOffset.width + value.translation.width,
                    height: settledOffset.height + value.translation.height)
            }
            .onEnded { _ in settledOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(PebbleMotion.animation(reduceMotion: reduceMotion)) { setScale(scale > 1 ? 1 : 2.5) }
    }

    private func setScale(_ value: CGFloat) {
        scale = value
        settledScale = value
        if value <= 1 {
            offset = .zero
            settledOffset = .zero
        }
    }
}

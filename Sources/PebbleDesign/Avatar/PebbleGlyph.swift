import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Pebble as a one-colour glyph: the avatar engine's own pebble with its two eyes cut out (the person, 2026-10-31: "i
/// wanted the pebble avatar in the apps bottom menu's pebble section where its a smiley face"). A template image, so
/// the tab bar tints it as it tints its symbols, selected or not. The face is the pose's own (the rest face looks up and
/// to the right, as Pebble's does); closed eyes make a blink.
///
/// A tab bar draws images, not live views, so the Pebble tab lives by swapping these: `MainTabs` blinks it now and
/// then, gives it Pebble's face for what Pebble is doing, and a happy one when the tab is tapped. Each glyph is drawn
/// once and kept.
public enum PebbleGlyph {
    /// The square the pebble is drawn in, in engine units: its radius is 65, so it fills most of the square.
    nonisolated static let box = 150.0

    private static var drawn: [String: Image] = [:]

    /// The glyph for `pose`, `side` points square, at the screen's `scale`.
    public static func image(pose: PebbleAvatar.Pose, eyesClosed: Bool = false, side: CGFloat = 28, scale: CGFloat = 3)
        -> Image
    {
        let key = "\(pose.rawValue) \(eyesClosed) \(side) \(scale)"
        if let kept = drawn[key] { return kept }
        let face = AvatarVisual.of(pose).face
        let tilt = tilt(of: pose)
        let renderer = ImageRenderer(
            content: Canvas { context, size in
                draw(face: face, lid: eyesClosed ? 0 : 1, tilt: tilt, in: &context, size: size)
            }
            .frame(width: side, height: side))
        renderer.scale = scale
        guard let cgImage = renderer.cgImage else { return Image(systemName: PebbleSymbol.tabPebble) }
        #if canImport(UIKit)
        let image = Image(
            uiImage: UIImage(cgImage: cgImage, scale: scale, orientation: .up).withRenderingMode(.alwaysTemplate))
        #else
        let image = Image(decorative: cgImage, scale: scale).renderingMode(.template)
        #endif
        drawn[key] = image
        return image
    }

    /// A glyph can't move, so the poses that move the pebble lean it instead: the celebration tips it the way Pebble's
    /// happy bounce does, and a sleepy pebble nods off as the avatar's own sleepy pose does.
    nonisolated static func tilt(of pose: PebbleAvatar.Pose) -> Double {
        switch pose {
        case .finished: -12
        case .sleepy: 10
        case .hover: 3
        default: 0
        }
    }

    /// The pebble filled, its eyes cleared out of it: in engine coordinates, as the avatar draws them.
    nonisolated static func draw(
        face: FaceExpression, lid: Double, tilt: Double = 0, in context: inout GraphicsContext, size: CGSize
    ) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        var ctx = context
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: side / box, y: side / box)
        ctx.rotate(by: .degrees(tilt))
        ctx.fill(AvatarShape.restingBody, with: .color(.black))
        let life = AvatarFace.liveliness(0, wander: 0, blink: false)
        let eyes = AvatarRenderer.eyePaths(face, life: life, still: true, lid: lid, offX: 0, offY: 0, veilEye: 1)
        ctx.blendMode = .destinationOut
        for eye in eyes {
            ctx.fill(eye.path, with: .color(.black.opacity(eye.alpha)))
        }
    }
}

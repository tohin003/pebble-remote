import CoreGraphics
import Foundation

/// Where the eyes look when something outside the pose leads them: the Mac's pointer over its companion, a finger on the
/// phone's (the vendored engine's `Look`, engine.ts; the mapping is companionPointer.ts `lookFor`).
///
/// `yaw` and `pitch` replace the pose's own direction as `mix` rises, so the eyes keep each expression's shape while the
/// finger decides where they point; the head's roll never follows. `wander` is what stays of the resting drift, so the
/// pebble holds the finger's direction instead of seeming to search for it.
nonisolated struct AvatarLook: Equatable, Sendable {
    var yaw: Double
    var pitch: Double
    var mix: Double
    var wander: Double

    /// The pose's own direction, with all of its drift.
    static let none = AvatarLook(yaw: 0, pitch: 0, mix: 0, wander: 1)
    /// How long the eyes take to catch up with a new direction (engine.ts `LOOK_MORPH`).
    static let morph = 0.24
    /// Steps per half axis (companionPointer.ts `GAZE_STEPS`): 17 positions, so a trembling finger doesn't shake the eyes.
    static let steps = 8.0

    /// Toward a direction in screen terms, x right and y down, each in -1...1.
    static func toward(_ direction: CGVector) -> AvatarLook {
        AvatarLook(yaw: quantize(direction.dx) * 40, pitch: -quantize(direction.dy) * 30, mix: 0.8, wander: 0.1)
    }

    static func quantize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let q = (min(max(value, -1), 1) * steps).rounded() / steps
        return q == 0 ? 0 : q
    }

    static func lerp(_ a: AvatarLook, _ b: AvatarLook, _ t: Double) -> AvatarLook {
        AvatarLook(
            yaw: a.yaw + (b.yaw - a.yaw) * t, pitch: a.pitch + (b.pitch - a.pitch) * t, mix: a.mix + (b.mix - a.mix) * t,
            wander: a.wander + (b.wander - a.wander) * t)
    }
}

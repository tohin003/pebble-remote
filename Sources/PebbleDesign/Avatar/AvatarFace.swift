import Foundation

// The pebble's face, ported from Pebble's vendored avatar engine (src/vendor/bloub face.ts, expressions.ts, math.ts;
// MIT, Copyright (c) 2026 Jérémy Perret; the full notice is in AvatarShape.swift).
//
// Two capsule eyes painted on a sphere, not laid flat: each eye takes the sphere's tangent frame for the head's
// orientation, projected orthographically, which gives the face its volume. Expressions move four levers: the head's
// orientation, the eyes' spacing, their proportions, and each eye's own tilt.

/// Head orientation in degrees: yaw right, pitch up, roll.
nonisolated struct HeadGaze: Equatable, Sendable {
    var yaw: Double
    var pitch: Double
    var roll: Double

    static func lerp(_ a: HeadGaze, _ b: HeadGaze, _ t: Double) -> HeadGaze {
        HeadGaze(yaw: a.yaw + (b.yaw - a.yaw) * t, pitch: a.pitch + (b.pitch - a.pitch) * t, roll: a.roll + (b.roll - a.roll) * t)
    }
}

/// One eye: width and height in ball radii, openness (1 open), tilt in degrees (top to the right).
nonisolated struct EyeShape: Equatable, Sendable {
    var w: Double
    var h: Double
    var open: Double = 1
    var tilt: Double = 0

    static func lerp(_ a: EyeShape, _ b: EyeShape, _ t: Double) -> EyeShape {
        EyeShape(w: a.w + (b.w - a.w) * t, h: a.h + (b.h - a.h) * t, open: a.open + (b.open - a.open) * t,
                 tilt: a.tilt + (b.tilt - a.tilt) * t)
    }
}

/// A face: where the head looks, how far apart the eyes sit (half the split, degrees on the sphere), and the two eyes
/// (inner, outer).
nonisolated struct FaceExpression: Equatable, Sendable {
    var gaze: HeadGaze
    var split: Double
    var eyes: (EyeShape, EyeShape)

    static func == (a: FaceExpression, b: FaceExpression) -> Bool {
        a.gaze == b.gaze && a.split == b.split && a.eyes.0 == b.eyes.0 && a.eyes.1 == b.eyes.1
    }

    static func lerp(_ a: FaceExpression, _ b: FaceExpression, _ t: Double) -> FaceExpression {
        FaceExpression(
            gaze: .lerp(a.gaze, b.gaze, t), split: a.split + (b.split - a.split) * t,
            eyes: (.lerp(a.eyes.0, b.eyes.0, t), .lerp(a.eyes.1, b.eyes.1, t)))
    }

    private static func pair(_ w: Double, _ h: Double, tilt: Double = 0, open: Double = 1) -> (EyeShape, EyeShape) {
        (EyeShape(w: w, h: h, open: open, tilt: tilt), EyeShape(w: w, h: h, open: open, tilt: -tilt))
    }

    // face.ts
    static let eyeSplit = 15.46
    static let eyeWidth = 0.186
    static let eyeHeight = 0.412
    static let restGaze = HeadGaze(yaw: 28.49, pitch: 28.62, roll: -13)

    // expressions.ts (the ones Pebble's poses use)
    static let neutre = FaceExpression(
        gaze: restGaze, split: eyeSplit, eyes: (EyeShape(w: eyeWidth, h: eyeHeight), EyeShape(w: eyeWidth, h: eyeHeight)))
    static let attentif = FaceExpression(gaze: HeadGaze(yaw: 4, pitch: 5, roll: -4), split: 16, eyes: pair(0.21, 0.44))
    static let heureux = FaceExpression(
        gaze: HeadGaze(yaw: 5, pitch: 9, roll: 0), split: 17, eyes: pair(0.27, 0.17, tilt: 14))
    static let triste = FaceExpression(
        gaze: HeadGaze(yaw: 3, pitch: -13, roll: 0), split: 16, eyes: pair(0.22, 0.4, tilt: -28))
    static let mefiant = FaceExpression(
        gaze: HeadGaze(yaw: 12, pitch: 6, roll: -6), split: 16, eyes: (EyeShape(w: 0.21, h: 0.4), EyeShape(w: 0.22, h: 0.15)))
    static let confus = FaceExpression(
        gaze: HeadGaze(yaw: -14, pitch: 3, roll: 8), split: 16.5,
        eyes: (EyeShape(w: 0.2, h: 0.44, tilt: -18), EyeShape(w: 0.28, h: 0.17, tilt: 14)))
    static let curieux = FaceExpression(
        gaze: HeadGaze(yaw: 16, pitch: -9, roll: -15), split: 16.5,
        eyes: (EyeShape(w: 0.24, h: 0.46, tilt: -8), EyeShape(w: 0.2, h: 0.38, tilt: -8)))
    static let fier = FaceExpression(gaze: HeadGaze(yaw: 5, pitch: 17, roll: 0), split: 17, eyes: pair(0.3, 0.15, tilt: 18))
    static let blase = FaceExpression(gaze: HeadGaze(yaw: -22, pitch: 2, roll: 0), split: 16, eyes: pair(0.3, 0.12))
    static let somnolent = FaceExpression(
        gaze: HeadGaze(yaw: 6, pitch: -9, roll: -3), split: 16, eyes: pair(0.2, 0.42, open: 0.42))
    /// The engine's "notify" state face: round eyes looking away from the dot (states.ts).
    static let notify = FaceExpression(
        gaze: HeadGaze(yaw: -21.94, pitch: -5.82, roll: -12.2), split: 18.89, eyes: pair(0.505, 0.498))
}

/// One eye placed on the sphere: centre (engine units), tangent frame `a b c d` (SVG matrix order), depth (> 0 is
/// visible).
nonisolated struct EyePose: Sendable {
    var x: Double
    var y: Double
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var depth: Double
}

nonisolated enum AvatarFace {
    typealias Vec3 = (x: Double, y: Double, z: Double)

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Turns two orthonormal vectors in their common plane (face.ts `spin`).
    private static func spin(_ u: Vec3, _ v: Vec3, _ angle: Double) -> (Vec3, Vec3) {
        let c = cos(angle), s = sin(angle)
        return (
            (u.x * c + v.x * s, u.y * c + v.y * s, u.z * c + v.z * s),
            (v.x * c - u.x * s, v.y * c - u.y * s, v.z * c - u.z * s)
        )
    }

    /// The head's frame, then both eyes' (face.ts `eyePoses`). Screen frame: x right, y down, z toward the viewer.
    static func eyePoses(_ gaze: HeadGaze, scale: Double, split: Double) -> (EyePose, EyePose) {
        var f: Vec3 = (0, 0, 1), right: Vec3 = (1, 0, 0), down: Vec3 = (0, 1, 0)
        (f, right) = spin(f, right, radians(gaze.yaw))
        (down, f) = spin(down, f, radians(gaze.pitch))
        (right, down) = spin(right, down, radians(gaze.roll))
        func build(_ side: Double) -> EyePose {
            let (ef, er) = spin(f, right, radians(split * side))
            return EyePose(x: ef.x * scale, y: ef.y * scale, a: er.x, b: er.y, c: down.x, d: down.y, depth: ef.z)
        }
        return (build(-1), build(1))
    }

    /// Seamless periodic 1D noise (math.ts `loopNoise`).
    static func loopNoise(_ t: Double, period: Double, seed: Double = 0) -> Double {
        let p = t / period * 2 * .pi
        return 0.55 * sin(p + seed) + 0.3 * sin(2 * p + seed * 1.7 + 1.1) + 0.15 * sin(3 * p + seed * 2.3 + 2.4)
    }

    /// Deterministic PRNG (mulberry32, math.ts `createRng`): the same sequence every time.
    struct Mulberry32 {
        var state: UInt32
        init(seed: UInt32) { state = seed }
        mutating func next() -> Double {
            state = state &+ 0x6d2b_79f5
            var t = (state ^ (state >> 15)) &* (1 | state)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// The blink calendar, drawn once (face.ts `BLINKS`): 1.9 to 4.6 s apart, sometimes a double blink.
    static let blinks: [Double] = {
        var rng = Mulberry32(seed: 0x5eed)
        var out: [Double] = []
        var t = 1.4
        while t < 900 {
            out.append(t)
            t += 1.9 + rng.next() * 2.7
            if rng.next() < 0.18 {
                out.append(t)
                t += 0.24
            }
        }
        return out
    }()

    static let blinkDuration = 0.18
    /// The calendar's length; later times wrap so the pebble keeps blinking (face.ts stops after 15 minutes).
    static let blinkPeriod = 900.0

    /// Eye openness at time `t`: 1 open, 0 shut (fast close, slightly slower reopen).
    static func blinkLid(_ t: Double) -> Double {
        guard t.isFinite, t >= 0 else { return 1 }
        let local = t.truncatingRemainder(dividingBy: blinkPeriod)
        // the last blink starting at or before `local`
        var lo = 0, hi = blinks.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if blinks[mid] <= local { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return 1 }
        let k = (local - blinks[lo - 1]) / blinkDuration
        guard k >= 0, k <= 1 else { return 1 }
        return k < 0.45 ? 1 - k / 0.45 : (k - 0.45) / 0.55
    }

    /// Life at rest (face.ts `liveliness`): slow gaze drift, blinks, a breath. A pure function of time.
    struct Liveliness {
        var dYaw: Double
        var dPitch: Double
        var dRoll: Double
        var lid: Double
        var driftX: Double
        var driftY: Double
        var breath: Double
    }

    static func liveliness(_ t: Double, wander: Double = 1, blink: Bool = true) -> Liveliness {
        Liveliness(
            dYaw: (loopNoise(t, period: 11.3, seed: 0.4) * 5.5 + loopNoise(t, period: 3.7, seed: 2.1) * 1.6) * wander,
            dPitch: (loopNoise(t, period: 9.1, seed: 1.3) * 4.2 + loopNoise(t, period: 4.3, seed: 0.7) * 1.3) * wander,
            dRoll: loopNoise(t, period: 13.7, seed: 3.2) * 2.2 * wander,
            lid: blink ? blinkLid(t) : 1,
            driftX: loopNoise(t, period: 7.9, seed: 1.9) * 0.006,
            driftY: loopNoise(t, period: 5.3, seed: 0.3) * 0.007,
            breath: 1 + sin(t / 3.4 * 2 * .pi) * 0.005
        )
    }

    /// A blink squashes the eye vertically on screen, never to nothing (face.ts `blinkScale`).
    static func blinkScale(_ lid: Double) -> Double { 0.06 + 0.94 * min(max(lid, 0), 1) }

    /// The ease-out the engine measured on its reference video (math.ts `easeOutQuint`).
    static func easeOutQuint(_ t: Double) -> Double {
        let c = min(max(t, 0), 1)
        return 1 - pow(1 - c, 5)
    }
}

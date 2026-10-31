import Foundation

/// The Veil: Stealth Lockdown's look on the pebble, ported from Pebble's `src/stealthVeil.ts` (Phase 33, D57, look A).
/// A pure function of the seconds since the switch last changed.
///
/// - Activation 1.25 s: gather (squash to 92 %, eyes close) 0-0.15 s; cloak (the dusk colour wipes down behind a bright
///   hem, one ping, stretch to 104 %) 0.15-0.6 s; wake (eyes reopen to a calm 80 %, the light rim fades in)
///   0.6-0.85 s; finale (the glass arrives) 0.85-1.25 s.
/// - Release 0.65 s: fold (glass and rim go) 0-0.25 s; lift (the colour wipes back up) 0.15-0.45 s; hop (3.5 % and one
///   blink) 0.45-0.65 s.
/// - Reduce Motion: one 0.3 s cross-fade each way; no squash, wipe, ping or blink.
/// - While on: a 70 %-opaque glass body and one 1.1 s shimmer every 6 s (none under Reduce Motion or when still).
nonisolated struct AvatarVeil: Equatable, Sendable {
    /// How far the dusk colour covers the body, 0...1 (the wipe edge, or the cross-fade).
    var cloak: Double
    /// The light rim's strength.
    var rim: Double
    /// The glass finish (body opacity runs from 1 to `glassOpacity`).
    var glass: Double
    /// Eye openness: 1 open, 0.8 calm, 0 closed.
    var eye: Double
    var sy: Double
    var sx: Double
    /// The bright line at the wipe edge.
    var hem: Double
    /// The ring's progress 0...1, or -1 when there is none.
    var ping: Double
    /// Reduce Motion: cross-fade the layers instead of wiping.
    var fade: Bool

    static let activate = 1.25
    static let release = 0.65
    static let fadeDuration = 0.3
    static let shimmerEvery = 6.0
    static let shimmerLength = 1.1
    static let glassOpacity = 0.7

    static let off = AvatarVeil(cloak: 0, rim: 0, glass: 0, eye: 1, sy: 1, sx: 1, hem: 0, ping: -1, fade: false)
    static let on = AvatarVeil(cloak: 1, rim: 1, glass: 1, eye: 0.8, sy: 1, sx: 1, hem: 0, ping: -1, fade: false)

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    private static func inCubic(_ t: Double) -> Double { t * t * t }
    private static func inOutCubic(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    private static func outBack(_ t: Double) -> Double { 1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2) }

    /// The Veil `dt` seconds after the switch went `on` (or off), starting from `from`.
    static func at(on: Bool, dt: Double, from: AvatarVeil? = nil, reduced: Bool) -> AvatarVeil {
        let from = from ?? (on ? .off : .on)
        if reduced {
            let c = inOutCubic(clamp(dt / fadeDuration))
            let f = on ? from.cloak + (1 - from.cloak) * c : from.cloak * (1 - c)
            return AvatarVeil(cloak: f, rim: f, glass: f, eye: 1 - 0.2 * f, sy: 1, sx: 1, hem: 0, ping: -1, fade: true)
        }
        var sy = 1.0, eye: Double, hem: Double, cloak: Double, rim: Double, glass: Double, ping = -1.0
        if on {
            cloak = from.cloak + (1 - from.cloak) * (dt < 0.15 ? 0 : inOutCubic(clamp((dt - 0.15) / 0.45)))
            rim = from.rim + (1 - from.rim) * outCubic(clamp((dt - 0.6) / 0.25))
            glass = from.glass + (1 - from.glass) * outCubic(clamp((dt - 0.85) / 0.4))
            if dt < 0.15 {
                sy = lerp(1, 0.92, outCubic(clamp(dt / 0.15)))
            } else if dt < 0.45 {
                sy = lerp(0.92, 1.04, outCubic((dt - 0.15) / 0.3))
            } else if dt < 0.75 {
                sy = lerp(1.04, 1, inOutCubic((dt - 0.45) / 0.3))
            }
            if dt < 0.06 {
                eye = lerp(from.eye, 0, clamp(dt / 0.06))
            } else if dt < 0.6 {
                eye = 0
            } else if dt < 0.85 {
                eye = 0.8 * outBack((dt - 0.6) / 0.25)
            } else {
                eye = 0.8
            }
            hem = dt > 0.15 && dt < 0.6 ? sin(.pi * (dt - 0.15) / 0.45) : 0
            if dt >= 0.15 && dt < 0.85 { ping = (dt - 0.15) / 0.7 }
        } else {
            glass = from.glass * (1 - inCubic(clamp(dt / 0.25)))
            rim = from.rim * (1 - clamp(dt / 0.2))
            cloak = from.cloak * (1 - inOutCubic(clamp((dt - 0.15) / 0.3)))
            if dt >= 0.45 && dt < 0.55 {
                sy = lerp(1, 1.035, outCubic((dt - 0.45) / 0.1))
            } else if dt >= 0.55 && dt < 0.65 {
                sy = lerp(1.035, 1, inOutCubic((dt - 0.55) / 0.1))
            }
            if dt < 0.42 {
                eye = from.eye
            } else if dt < 0.48 {
                eye = lerp(from.eye, 0, (dt - 0.42) / 0.06)
            } else if dt < 0.62 {
                eye = outCubic((dt - 0.48) / 0.14)
            } else {
                eye = 1
            }
            hem = dt > 0.15 && dt < 0.45 && from.cloak > 0.05 ? sin(.pi * (dt - 0.15) / 0.3) : 0
        }
        return AvatarVeil(
            cloak: cloak, rim: rim, glass: glass, eye: eye, sy: sy, sx: 1 + (1 - sy) * 0.7, hem: hem, ping: ping,
            fade: false)
    }

    /// Whether a change made `dt` seconds ago is still moving.
    static func moving(on: Bool, dt: Double, reduced: Bool) -> Bool {
        dt < (reduced ? fadeDuration : on ? activate : release)
    }

    /// The shimmer band's progress and strength `t` seconds after the activation ended; nil between shimmers.
    static func shimmer(_ t: Double) -> (x: Double, opacity: Double)? {
        guard t >= 0 else { return nil }
        let c = t.truncatingRemainder(dividingBy: shimmerEvery)
        guard c < shimmerLength else { return nil }
        let p = c / shimmerLength
        return (inOutCubic(p), sin(.pi * p))
    }
}

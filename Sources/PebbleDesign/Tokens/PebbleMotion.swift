import SwiftUI

/// Motion with Pebble's rules (design studies 19 §2.5 and 22 §3.3): purposeful, quiet, under three luminance changes
/// a second, and static or a short cross-fade under Reduce Motion. Status words rotate inside one meaning only.
nonisolated public enum PebbleMotion {
    // Pebble's own cadences (statusWords.ts, pinned by its tests)
    /// A status word's synonyms rotate this often, only inside one key (`ROTATE_MS`).
    public static let rotateInterval: TimeInterval = 3
    /// At most one spoken status announcement per this window (`ANNOUNCE_MS`).
    public static let announceInterval: TimeInterval = 10
    /// Progress-driven updates at most this often (`COALESCE_MS`, 4 Hz).
    public static let coalesceInterval: TimeInterval = 0.25
    /// The first activity word waits this long, so a quick reply never flashes "Thinking" (Phase 24, V1-159).
    public static let activityGrace: TimeInterval = 0.5
    /// A calm avatar pose settles to a still frame after this (Avatar.vue `HOLD_SECONDS`).
    public static let avatarHold: TimeInterval = 8

    // The Veil (stealthVeil.ts)
    public static let veilActivate: TimeInterval = 1.25
    public static let veilRelease: TimeInterval = 0.65
    /// Reduce Motion's cross-fade, each way.
    public static let veilFade: TimeInterval = 0.3

    // Curves
    /// Most state changes: a quick, critically damped spring.
    public static let standard: Animation = .snappy(duration: 0.3)
    /// Things appearing (a new card, the run bar): a soft spring without bounce.
    public static let appear: Animation = .smooth(duration: 0.35)
    /// Small feedback (a chip changing, a toast): Pebble's 0.2 s.
    public static let quick: Animation = .easeOut(duration: 0.2)
    /// Under Reduce Motion: an opacity-only fade.
    public static let reducedFade: Animation = .easeInOut(duration: 0.3)

    /// The animation to use given the Reduce Motion setting: `reducedFade` (pair it with an opacity-only transition)
    /// or nil to change instantly.
    public static func animation(_ base: Animation = standard, reduceMotion: Bool, fade: Bool = true) -> Animation? {
        reduceMotion ? (fade ? reducedFade : nil) : base
    }

    /// A transition that moves and fades, or only fades under Reduce Motion.
    public static func transition(edge: Edge = .bottom, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

extension View {
    /// `animation(_:value:)` that follows Reduce Motion: `PebbleMotion.reducedFade` instead of movement.
    public func pebbleAnimation<V: Equatable>(_ animation: Animation = PebbleMotion.standard, value: V) -> some View {
        modifier(PebbleAnimationModifier(animation: animation, value: value))
    }
}

private struct PebbleAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(PebbleMotion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

import Foundation

/// Movement inside a pose, ported from Pebble's `src/avatarMotion.ts`. Pebble's state chooses the pose; time only
/// supplies movement within it. Cue scale and opacity pulse at 0.5 Hz and body sway stays at or under 0.5 Hz, far
/// under three luminance changes a second. Reduce Motion gives the same still frame at every time.
nonisolated struct AvatarMotion {
    static let cueHertz = 0.5

    var x = 0.0
    var y = 0.0
    /// Degrees.
    var tilt = 0.0
    var sx = 1.0
    var sy = 1.0
    /// Three cue elements pulsing in turn, each 0...1.
    var pulse: (Double, Double, Double) = (0.6, 0.6, 0.6)
    /// Seconds used for the orbit cue's turn (0 when still).
    var t = 0.0

    static func of(_ pose: PebbleAvatar.Pose, seconds: Double, reduced: Bool) -> AvatarMotion {
        let t = reduced || !seconds.isFinite ? 0 : seconds
        func wave(_ hz: Double, _ offset: Double = 0) -> Double { sin(2 * .pi * hz * t + offset) }
        var m = AvatarMotion()
        m.t = t
        switch pose {
        case .thinking, .working, .delegating:
            m.tilt = 6 * wave(0.27)
            m.y = -3 * (1 + wave(0.37))
        case .writing:
            m.y = -2 * (1 + wave(0.45))
            m.tilt = 2 * wave(0.3)
        case .sending:
            m.y = -2 * (1 + wave(0.5))
        case .loading, .reconnecting:
            m.y = -4 * (1 + wave(pose == .loading ? 0.48 : 0.3))
            m.sy = 1 + 0.025 * wave(0.48)
        case .reading, .searching:
            m.tilt = 4 * wave(0.32)
            m.x = 2 * wave(pose == .searching ? 0.45 : 0.32)
        case .editing, .viewing:
            m.y = -5 * abs(wave(0.25))
            m.sx = 1 + 0.03 * wave(0.48)
            m.sy = 1 - 0.03 * wave(0.48)
        case .testing, .running:
            m.tilt = 5 * wave(0.48)
            m.y = -3 * abs(wave(0.24))
        case .review, .question:
            m.tilt = 5
            m.y = -2 * wave(0.32)
        case .finished:
            m.y = -6 * abs(wave(0.25))
            m.tilt = 5 * wave(0.25)
        case .sleepy, .paused:
            m.tilt = (pose == .sleepy ? 12 : 6) + 2 * wave(0.16)
            m.sy = 0.97
        case .problem, .offline:
            m.tilt = -7
            m.y = 2
        case .blocked, .uncertain:
            m.tilt = -3
        case .stopped:
            m.tilt = -4
        case .tap:
            m.y = -3
        case .hover:
            m.tilt = 3
        case .idle, .notify:
            break
        }
        if reduced {
            m.x = 0
            m.y = 0
            m.tilt = pose == .sleepy ? 8 : 0
            m.sx = 1
            m.sy = 1
            m.pulse = (0.6, 0.6, 0.6)
        } else {
            let p = { (i: Double) in 0.5 + 0.5 * wave(cueHertz, -i * 2.1) }
            m.pulse = (p(0), p(1), p(2))
        }
        return m
    }
}

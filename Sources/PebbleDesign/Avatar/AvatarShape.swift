import CoreGraphics
import Foundation
import SwiftUI

// The pebble's body, ported from the avatar engine Pebble vendors (src/vendor/bloub: skins.ts "galet", shape.ts).
//
// bloub is MIT-licensed:
//   MIT License. Copyright (c) 2026 Jérémy Perret.
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//   documentation files (the "Software"), to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//   permit persons to whom the Software is furnished to do so, subject to the following conditions:
//   The above copyright notice and this permission notice shall be included in all copies or substantial portions of
//   the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO
//   THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//   SOFTWARE.
// The same notice covers AvatarFace.swift, which ports face.ts and expressions.ts.

/// Coordinates follow the engine: a 220 x 220 box centred on the origin (Avatar.vue's viewBox -110...110), y down,
/// and a resting ball of radius `scale` = 65 (Avatar.vue's `new BotEngine(65, ...)`).
nonisolated enum AvatarShape {
    static let samples = 64
    static let viewBox: Double = 220
    static let scale: Double = 65

    static let angles: [Double] = (0..<samples).map { Double($0) / Double(samples) * 2 * .pi }

    /// The "galet": a circle bent by two low harmonics, irregular but smooth, normalised so its widest radius is 1.02.
    static let pebbleRadii: [Double] = {
        let raw = angles.map { a in 1 + 0.075 * cos(2 * a + 0.5) + 0.035 * cos(3 * a + 2.1) }
        let peak = raw.max() ?? 1
        return raw.map { $0 * 1.02 / peak }
    }()

    /// The profile's radius in any direction, between the two nearest samples (`radiusAtAngle`).
    static func radius(at angle: Double, radii: [Double] = pebbleRadii) -> Double {
        let n = Double(radii.count)
        var unit = (angle / (2 * .pi)).truncatingRemainder(dividingBy: 1)
        if unit < 0 { unit += 1 }
        let t = unit * n
        let i = Int(t.rounded(.down)) % radii.count
        let j = (i + 1) % radii.count
        let f = t - t.rounded(.down)
        return radii[i] + (radii[j] - radii[i]) * f
    }

    /// The body's points: the profile, squashed in screen space, scaled and offset (`toPoints`).
    static func points(radii: [Double] = pebbleRadii, sx: Double = 1, sy: Double = 1, cx: Double = 0, cy: Double = 0)
        -> [CGPoint]
    {
        var out: [CGPoint] = []
        out.reserveCapacity(radii.count)
        for (r, a) in zip(radii, angles) {
            let x: Double = (r * cos(a) * sx + cx) * scale
            let y: Double = (r * sin(a) * sy + cy) * scale
            out.append(CGPoint(x: x, y: y))
        }
        return out
    }

    /// A closed Catmull-Rom curve through the points (`closedPath`, tension 1/6).
    static func closedPath(_ pts: [CGPoint], tension: Double = 1.0 / 6) -> Path {
        var path = Path()
        let n = pts.count
        guard n >= 3 else { return path }
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) * tension, y: p1.y + (p2.y - p0.y) * tension)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) * tension, y: p2.y - (p3.y - p1.y) * tension)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    /// The pebble's outline at rest, in engine coordinates.
    static let restingBody: Path = closedPath(points())

    /// A capsule (stadium) centred on the origin: the exact shape of the eyes (`capsulePath`).
    static func capsule(width: Double, height: Double) -> Path {
        let w = max(width, 0.01), h = max(height, 0.01)
        let r = min(w, h) / 2
        return Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: r, style: .circular)
    }
}

/// The pebble's silhouette as a SwiftUI shape, for glyphs, masks and placeholders (fills its frame, keeps the
/// aspect of the engine's 220-unit box).
nonisolated public struct PebbleShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let body = AvatarShape.restingBody
        let bounds = body.boundingRect
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let k = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return body.applying(transform)
    }
}

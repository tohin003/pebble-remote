import SwiftUI

/// Draws one frame of the pebble into a Canvas: the body, the eyes, the Veil, the cue and the notification dot, as
/// Avatar.vue draws its SVG (same coordinates, same layers).
nonisolated struct AvatarFrame {
    var pose: PebbleAvatar.Pose
    /// The face to draw (already blended between poses).
    var face: FaceExpression
    /// Seconds since the avatar appeared: drives blinks, drift, breath and motion.
    var seconds: Double
    /// A still frame: no motion, eyes open (Reduce Motion, or `animated: false`).
    var still: Bool
    /// Seconds since a pose change that blinks (entering the notification pose), or nil.
    var forcedBlink: Double?
    /// Seconds since the notification dot appeared, or nil when it shows without its pop.
    var dotAge: Double?
    var veil: AvatarVeil
    /// The shimmer band while the Veil is on, or nil.
    var shine: (x: Double, opacity: Double)?
    /// Where something outside the pose leads the eyes (a finger), already caught up to this instant.
    var look = AvatarLook.none

    var showsVeil: Bool { veil.cloak > 0.001 || veil.rim > 0.001 || veil.ping >= 0 }
}

nonisolated enum AvatarRenderer {
    static let r = AvatarShape.scale

    static func draw(_ frame: AvatarFrame, in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        let fine = side >= PebbleSize.avatarFineDetail
        var ctx = context
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: side / AvatarShape.viewBox, y: side / AvatarShape.viewBox)

        let visual = AvatarVisual.of(frame.pose)
        let motion = AvatarMotion.of(frame.pose, seconds: frame.seconds, reduced: frame.still)
        let life = AvatarFace.liveliness(frame.still ? 0 : frame.seconds, wander: frame.look.wander)

        // Eye openness: the blink calendar, a blink forced by the pose change, and the face's own lids.
        var lid = frame.still ? 1 : life.lid
        if let forced = frame.forcedBlink, !frame.still {
            let k = min(max(forced / 0.2, 0), 1)
            if k < 1 { lid = min(lid, abs(k * 2 - 1)) }
        }
        let offX = life.driftX, offY = life.driftY
        let body = AvatarShape.closedPath(AvatarShape.points(sy: life.breath, cx: offX, cy: offY))
        let eyes = eyePaths(frame.face, life: life, still: frame.still, lid: lid, offX: offX, offY: offY,
                            veilEye: frame.veil.eye, look: frame.look)

        // The pebble, moving inside its pose
        var moved = ctx
        moved.translateBy(x: motion.x, y: motion.y)
        moved.rotate(by: .degrees(motion.tilt))
        moved.scaleBy(x: motion.sx, y: motion.sy)
        var squashed = moved
        if frame.veil.sy != 1 {
            squashed.translateBy(x: 0, y: 66 * (1 - frame.veil.sy))
            squashed.scaleBy(x: frame.veil.sx, y: frame.veil.sy)
        }
        // The notification dot sits on the outline, in a notch cut from the body (the engine's `notch`).
        var dot: (center: CGPoint, radius: Double)?
        if visual.dot {
            let angle = -42.0 * .pi / 180
            let fit = AvatarShape.radius(at: angle)
            var radius = 0.15
            if let age = frame.dotAge, !frame.still {
                let p = min(max(age / 0.45, 0), 1)
                if p < 1 { radius *= 1 + (1.14 - 1) * sin(p * .pi) * (1 - p * 0.35) }
            }
            let center = CGPoint(x: (cos(angle) * 1.003 * fit + offX) * r, y: (sin(angle) * 1.003 * fit + offY) * r)
            dot = (center, radius * r)
        }
        drawBody(frame, body: body, eyes: eyes, dot: dot, fine: fine, side: side, in: &squashed)
        if fine, frame.veil.ping >= 0 {
            let ping = frame.veil.ping
            let grow = 1 + (16.0 / 66) * (1 - pow(1 - ping, 5))
            let ring = Path(ellipseIn: CGRect(x: -66 * grow, y: -66 * grow, width: 132 * grow, height: 132 * grow))
            moved.stroke(
                ring, with: .color(PebbleColor.avatarStealthGlow.opacity(0.85 * (1 - ping))),
                lineWidth: 3.5 - 2.8 * ping)
        }

        // The cue stays put while the body moves (as in Avatar.vue).
        drawCue(visual.cue, motion: motion, still: frame.still, in: &ctx)
    }

    /// The two eyes as paths in engine coordinates, with their opacity (engine.ts, "yeux").
    static func eyePaths(_ face: FaceExpression, life: AvatarFace.Liveliness, still: Bool, lid: Double, offX: Double,
                         offY: Double, veilEye: Double, look: AvatarLook = .none) -> [(path: Path, alpha: Double)] {
        // A look replaces the pose's direction as its mix rises; the drift adds after it, and the roll never follows
        // (engine.ts: the head's -13 degree lean is the pebble's signature).
        let gaze = HeadGaze(
            yaw: face.gaze.yaw + (look.yaw - face.gaze.yaw) * look.mix + life.dYaw,
            pitch: face.gaze.pitch + (look.pitch - face.gaze.pitch) * look.mix + life.dPitch,
            roll: face.gaze.roll + life.dRoll)
        let poses = AvatarFace.eyePoses(gaze, scale: r, split: face.split)
        var out: [(Path, Double)] = []
        for (pose, shape) in [(poses.0, face.eyes.0), (poses.1, face.eyes.1)] where pose.depth > 0.02 {
            let fit = AvatarShape.radius(at: atan2(pose.y, pose.x))
            let phi = shape.tilt * .pi / 180
            let cp = cos(phi), sp = sin(phi)
            let ax = pose.a * cp + pose.c * sp
            let ay = pose.b * cp + pose.d * sp
            let cx = -pose.a * sp + pose.c * cp
            let cy = -pose.b * sp + pose.d * cp
            let k = AvatarFace.blinkScale(min(lid, shape.open))
            let matrix = CGAffineTransform(
                a: ax, b: ay * k, c: cx, d: cy * k, tx: pose.x * fit + offX * r, ty: pose.y * fit + offY * r)
            let capsule = AvatarShape.capsule(width: shape.w * r, height: shape.h * r)
            // The Veil's eyes (closing in the cast, a calm 80 % while on): squashed along the eye's own axis before the
            // matrix (Avatar.vue `eyeTransform`); 1 when the Veil is off.
            let lids = CGAffineTransform(scaleX: 1, y: max(0.06, min(veilEye, 1))).concatenating(matrix)
            out.append((capsule.applying(veilEye >= 0.999 ? matrix : lids), min(max(pose.depth / 0.12, 0), 1)))
        }
        return out
    }

    static func drawBody(_ frame: AvatarFrame, body: Path, eyes: [(path: Path, alpha: Double)],
                         dot: (center: CGPoint, radius: Double)?, fine: Bool, side: CGFloat,
                         in context: inout GraphicsContext) {
        let veil = frame.veil
        let edge = -78 + 156 * veil.cloak
        var ctx = context
        if let dot {
            // Everything but a ring around the dot (even-odd: the box minus the notch).
            let notch = dot.radius + 0.054 * r
            var mask = Path(CGRect(x: -140, y: -140, width: 280, height: 280))
            mask.addEllipse(in: CGRect(x: dot.center.x - notch, y: dot.center.y - notch, width: 2 * notch, height: 2 * notch))
            ctx.clip(to: mask, style: FillStyle(eoFill: true))
        }
        defer {
            if let dot {
                let d = dot.radius
                context.fill(
                    Path(ellipseIn: CGRect(x: dot.center.x - d, y: dot.center.y - d, width: 2 * d, height: 2 * d)),
                    with: .color(PebbleColor.accent))
            }
        }

        // The pebble itself, below the wipe edge (or fading out under Reduce Motion)
        ctx.drawLayer { base in
            if frame.showsVeil {
                if veil.fade {
                    base.opacity = 1 - veil.cloak
                } else {
                    base.clip(to: Path(CGRect(x: -110, y: edge, width: 220, height: max(0, 110 - edge))))
                }
            }
            base.fill(body, with: .color(PebbleColor.avatar))
            for eye in eyes {
                base.fill(eye.path, with: .color(PebbleColor.avatarEye.opacity(eye.alpha)))
            }
        }
        guard frame.showsVeil else { return }

        // The dusk body above the wipe edge
        ctx.drawLayer { cloak in
            if veil.fade {
                cloak.opacity = veil.cloak
            } else {
                cloak.clip(to: Path(CGRect(x: -110, y: -110, width: 220, height: max(0, edge + 110))))
            }
            if fine {
                let box = body.boundingRect
                let glass = Gradient(stops: [
                    .init(color: PebbleColor.avatarStealthHi, location: 0),
                    .init(color: PebbleColor.avatarStealth, location: 0.75),
                ])
                cloak.drawLayer { glassLayer in
                    glassLayer.opacity = 1 - (1 - AvatarVeil.glassOpacity) * veil.glass
                    glassLayer.fill(
                        body,
                        with: .linearGradient(
                            glass, startPoint: CGPoint(x: box.minX + 0.15 * box.width, y: box.minY),
                            endPoint: CGPoint(x: box.minX + 0.85 * box.width, y: box.maxY)))
                }
                cloak.drawLayer { shineLayer in
                    shineLayer.clip(to: body)
                    var highlight = shineLayer
                    highlight.translateBy(x: -26, y: -30)
                    highlight.rotate(by: .degrees(-35))
                    highlight.fill(
                        Path(ellipseIn: CGRect(x: -20, y: -9, width: 40, height: 18)),
                        with: .color(.white.opacity(0.2 * veil.glass)))
                    if let shine = frame.shine {
                        var band = shineLayer
                        band.translateBy(x: -130 + 260 * shine.x, y: 0)
                        band.rotate(by: .degrees(22))
                        band.opacity = shine.opacity * veil.glass
                        let sheen = Gradient(stops: [
                            .init(color: .white.opacity(0), location: 0),
                            .init(color: .white.opacity(0.55), location: 0.5),
                            .init(color: .white.opacity(0), location: 1),
                        ])
                        band.fill(
                            Path(CGRect(x: -20, y: -140, width: 40, height: 280)),
                            with: .linearGradient(sheen, startPoint: CGPoint(x: -20, y: 0), endPoint: CGPoint(x: 20, y: 0)))
                    }
                }
            } else {
                cloak.fill(body, with: .color(PebbleColor.avatarStealth))
            }
            for eye in eyes {
                cloak.fill(eye.path, with: .color(PebbleColor.avatarStealthEye.opacity(eye.alpha)))
            }
        }

        // The light rim and the bright hem at the wipe edge, inside the body only
        ctx.drawLayer { rim in
            rim.clip(to: body)
            let width = fine ? 5 : 2 * 1.3 * AvatarShape.viewBox / max(side, 1)
            rim.stroke(body, with: .color(PebbleColor.avatarStealthRim.opacity(0.95 * veil.rim)), lineWidth: width)
            if veil.hem > 0 {
                rim.fill(
                    Path(CGRect(x: -110, y: edge - 0.9, width: 220, height: 1.8)),
                    with: .color(PebbleColor.avatarStealthRim.opacity(0.95 * veil.hem)))
            }
        }
    }

    /// The cue above the pebble (Avatar.vue `.avatar-cues`), in the avatar's colour.
    static func drawCue(_ cue: AvatarVisual.Cue, motion: AvatarMotion, still: Bool, in ctx: inout GraphicsContext) {
        let ink = PebbleColor.avatar
        let pulse = [motion.pulse.0, motion.pulse.1, motion.pulse.2]
        switch cue {
        case .none:
            break
        case .thought:
            for i in 1...3 {
                let p = pulse[i - 1]
                let radius = 2.5 + p
                let center = CGPoint(x: -18 + Double(i) * 10, y: -76)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                    with: .color(ink.opacity(0.35 + 0.65 * p)))
            }
        case .orbit:
            var turn = ctx
            turn.rotate(by: .degrees(still ? -30 : motion.t * 85))
            for i in 1...3 {
                let a = Double(i) * 2.094
                let radius = 4 - Double(i) * 0.6
                let center = CGPoint(x: 76 * cos(a), y: 76 * sin(a))
                turn.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                    with: .color(ink.opacity(1 - Double(i) * 0.2)))
            }
        case .scan:
            var line = Path()
            let y = -76 + (pulse[0] - 0.5) * 6
            line.move(to: CGPoint(x: -28, y: y))
            line.addLine(to: CGPoint(x: 28, y: y))
            ctx.stroke(
                line, with: .color(ink.opacity(0.65)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [18, 6, 6, 6]))
        case .spark, .celebrate:
            let spots = [CGPoint(x: -58, y: -46), CGPoint(x: 57, y: -48), CGPoint(x: 0, y: -77)]
            var plus = Path()
            plus.move(to: CGPoint(x: -5, y: 0))
            plus.addLine(to: CGPoint(x: 5, y: 0))
            plus.move(to: CGPoint(x: 0, y: -5))
            plus.addLine(to: CGPoint(x: 0, y: 5))
            for (i, spot) in spots.enumerated() {
                var mark = ctx
                mark.translateBy(x: spot.x, y: spot.y)
                mark.rotate(by: .degrees((pulse[i] - 0.5) * 40))
                mark.scaleBy(x: 0.75 + 0.25 * pulse[i], y: 0.75 + 0.25 * pulse[i])
                mark.stroke(plus, with: .color(ink), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            }
        case .attention:
            var bang = Path()
            bang.move(to: CGPoint(x: 0, y: -81))
            bang.addLine(to: CGPoint(x: 0, y: -73))
            bang.move(to: CGPoint(x: 0, y: -67))
            bang.addLine(to: CGPoint(x: 0, y: -66))
            ctx.stroke(bang, with: .color(ink), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        case .sleep:
            var z = Path()
            z.move(to: CGPoint(x: 39, y: -65))
            z.addLine(to: CGPoint(x: 48, y: -65))
            z.addLine(to: CGPoint(x: 39, y: -56))
            z.addLine(to: CGPoint(x: 48, y: -56))
            z.move(to: CGPoint(x: 52, y: -77))
            z.addLine(to: CGPoint(x: 59, y: -77))
            z.addLine(to: CGPoint(x: 52, y: -70))
            z.addLine(to: CGPoint(x: 59, y: -70))
            ctx.stroke(
                z, with: .color(ink.opacity(0.4 + 0.4 * pulse[0])),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        case .sigh:
            var drop = Path()
            drop.move(to: CGPoint(x: -54, y: -43))
            drop.addQuadCurve(to: CGPoint(x: -54, y: -31), control: CGPoint(x: -59, y: -35))
            drop.addQuadCurve(to: CGPoint(x: -54, y: -43), control: CGPoint(x: -49, y: -35))
            ctx.fill(drop, with: .color(ink.opacity(0.6)))
        }
    }
}

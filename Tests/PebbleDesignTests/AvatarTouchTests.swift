import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import PebbleDesign

// The Pebble tab's companion answers a touch as the Mac's answers its pointer (the person, 2026-10-31). The two touch
// poses are Pebble's own rows (companionState.ts row 16, avatarMotion.ts), and the eyes follow by companionPointer.ts.

struct AvatarTouchTests {
    @Test func theTouchPosesArePebblesRowSixteen() {
        #expect(AvatarVisual.of(.hover).face == .attentif)
        #expect(AvatarVisual.of(.tap).face == .heureux)
        for pose in [PebbleAvatar.Pose.hover, .tap] {
            #expect(pose.status == nil)
            #expect(pose.holds)
            #expect(AvatarVisual.of(pose).cue == .none && !AvatarVisual.of(pose).dot)
        }
        #expect(AvatarMotion.of(.tap, seconds: 3, reduced: false).y == -3)
        #expect(AvatarMotion.of(.hover, seconds: 3, reduced: false).tilt == 3)
        // Reduce Motion: no hop, no lean
        #expect(AvatarMotion.of(.tap, seconds: 3, reduced: true).y == 0)
        #expect(AvatarMotion.of(.hover, seconds: 3, reduced: true).tilt == 0)
    }

    @Test func aDirectionBecomesPebblesLook() {
        let right = AvatarLook.toward(CGVector(dx: 1, dy: 0))
        #expect(right == AvatarLook(yaw: 40, pitch: 0, mix: 0.8, wander: 0.1))
        // y is down on the screen and up for the head
        #expect(AvatarLook.toward(CGVector(dx: 0, dy: 1)).pitch == -30)
        #expect(AvatarLook.toward(CGVector(dx: 0, dy: -1)).pitch == 30)
        // beyond the rim it holds at full turn; a trembling finger moves in eighths
        #expect(AvatarLook.toward(CGVector(dx: 3, dy: 0)).yaw == 40)
        #expect(AvatarLook.quantize(0.30) == 0.25)
        #expect(AvatarLook.quantize(-0.04) == 0)
        #expect(AvatarLook.quantize(.nan) == 0)
    }

    @Test func theEyesCatchUpWithANewLook() {
        var timeline = AvatarTimeline()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let target = AvatarLook.toward(CGVector(dx: 1, dy: 0))
        timeline.look(to: target, at: start)
        #expect(timeline.look(at: start) == .none)
        let midway = timeline.look(at: start.addingTimeInterval(AvatarLook.morph / 2))
        #expect(midway.yaw > 0 && midway.yaw < 40)
        #expect(timeline.look(at: start.addingTimeInterval(AvatarLook.morph)) == target)
        // letting go returns the eyes from wherever they are
        timeline.look(to: .none, at: start.addingTimeInterval(AvatarLook.morph / 2))
        let back = timeline.look(at: start.addingTimeInterval(AvatarLook.morph / 2))
        #expect(abs(back.yaw - midway.yaw) < 1e-9)
    }

    @Test func aLookTurnsTheEyes() {
        let face = FaceExpression.neutre
        let life = AvatarFace.liveliness(0, wander: 0)
        let rest = AvatarRenderer.eyePaths(face, life: life, still: true, lid: 1, offX: 0, offY: 0, veilEye: 1)
        let looking = AvatarRenderer.eyePaths(
            face, life: life, still: true, lid: 1, offX: 0, offY: 0, veilEye: 1,
            look: .toward(CGVector(dx: -1, dy: 0)))
        #expect(rest.count == looking.count)
        #expect(rest.map { $0.path.boundingRect } != looking.map { $0.path.boundingRect })
    }
}

// The Pebble tab's icon is Pebble's own glyph (the person, 2026-10-31: not a smiley): the engine's pebble, one colour,
// its eyes cut out so the tab bar's tint shows them.
struct PebbleGlyphTests {
    @Test func theGlyphLeansWhereThePebbleWouldMove() {
        #expect(PebbleGlyph.tilt(of: .finished) == -12)
        #expect(PebbleGlyph.tilt(of: .sleepy) == 10)
        #expect(PebbleGlyph.tilt(of: .idle) == 0 && PebbleGlyph.tilt(of: .thinking) == 0)
    }

    @Test func theGlyphIsTheBodyWithItsEyesCutOut() throws {
        let side = PebbleGlyph.box  // one point per engine unit
        let renderer = ImageRenderer(
            content: Canvas { context, size in
                PebbleGlyph.draw(face: .neutre, lid: 1, in: &context, size: size)
            }
            .frame(width: side, height: side))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let alpha = try Self.alphas(image)
        func at(_ x: Double, _ y: Double) -> UInt8 { alpha[Int(y) * image.width + Int(x)] }

        #expect(at(2, 2) == 0, "outside the pebble")
        #expect(at(side / 2 - 30, side / 2 + 20) > 200, "the body, away from the eyes")
        let life = AvatarFace.liveliness(0, wander: 0, blink: false)
        let eye = try #require(
            AvatarRenderer.eyePaths(.neutre, life: life, still: true, lid: 1, offX: 0, offY: 0, veilEye: 1).first)
        let centre = CGPoint(x: eye.path.boundingRect.midX + side / 2, y: eye.path.boundingRect.midY + side / 2)
        #expect(at(centre.x, centre.y) < 40, "an eye, cut out")
    }

    /// The image's alpha, one byte per pixel, rows from the top.
    private static func alphas(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height)
        let context = try #require(
            CGContext(
                data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}

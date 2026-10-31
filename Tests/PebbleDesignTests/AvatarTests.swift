import Foundation
import PebbleProtocol
import Testing

@testable import PebbleDesign

/// The avatar port keeps Pebble's engine's numbers (bloub's galet, its face model and blink calendar), its poses
/// (companionState.ts) and the Veil's timings (stealthVeil.ts). Reference values were computed from Pebble's
/// TypeScript formulas.
struct AvatarTests {
    @Test func theGaletIsPebblesShape() {
        let radii = AvatarShape.pebbleRadii
        #expect(radii.count == 64)
        #expect(abs((radii.max() ?? 0) - 1.02) < 1e-12)
        #expect(abs((radii.min() ?? 0) - 0.829653618339829) < 1e-12)
        #expect(abs(radii[0] - 0.9765373800218337) < 1e-12)
        #expect(abs(radii[48] - 0.8422079621103316) < 1e-12)
        // radiusAtAngle interpolates and wraps
        #expect(abs(AvatarShape.radius(at: 0) - radii[0]) < 1e-12)
        #expect(abs(AvatarShape.radius(at: 2 * .pi) - radii[0]) < 1e-9)
        #expect(abs(AvatarShape.radius(at: -2 * .pi / 64) - radii[63]) < 1e-9)
    }

    @Test func theBlinkCalendarIsPebbles() {
        var rng = AvatarFace.Mulberry32(seed: 0x5eed)
        let first = (0..<4).map { _ in rng.next() }
        let expected = [0.7100320369936526, 0.286336648510769, 0.9519026265479624, 0.10175976227037609]
        for (a, b) in zip(first, expected) { #expect(abs(a - b) < 1e-15) }
        #expect(AvatarFace.blinks.count == 317)
        #expect(AvatarFace.blinks.prefix(4).elementsEqual([1.4, 5.217086499882862, 9.687223591562361, 9.927223591562361]) {
            abs($0 - $1) < 1e-9
        })
        #expect(AvatarFace.blinkLid(0) == 1)
        #expect(AvatarFace.blinkLid(1.4 + 0.18 * 0.45) < 1e-9)  // shut
        #expect(AvatarFace.blinkLid(1.4 + 0.18) > 0.999)  // open again
        #expect(AvatarFace.blinkLid(1.4 + 0.25) == 1)
        #expect(AvatarFace.blinkLid(900 + 1.4 + 0.18 * 0.45) < 1e-9)  // keeps blinking after 15 minutes
        #expect(AvatarFace.blinkScale(0) == 0.06)
    }

    @Test func theRestingFaceLooksUpAndRight() {
        let face = FaceExpression.neutre
        let eyes = AvatarFace.eyePoses(face.gaze, scale: AvatarShape.scale, split: face.split)
        for eye in [eyes.0, eyes.1] {
            #expect(eye.depth > 0.5)
            #expect(eye.x > 0 && eye.y < 0)
        }
        #expect(eyes.0.x < eyes.1.x)
    }

    @Test func everyStatusKeyHasAPoseAndBack() {
        for key in StatusKey.allCases {
            let pose = PebbleAvatar.Pose(status: key)
            #expect(pose.status == key, "\(key)")
        }
        #expect(PebbleAvatar.Pose(status: nil) == .idle)
        #expect(PebbleAvatar.Pose(status: .error) == .problem)
        for pose in [PebbleAvatar.Pose.idle, .sleepy, .finished, .stopped, .notify] { #expect(pose.status == nil) }
        #expect(AvatarVisual.of(.question).dot && AvatarVisual.of(.notify).dot)
        #expect(!AvatarVisual.of(.review).dot && AvatarVisual.of(.review).cue == .attention)
        #expect(AvatarVisual.of(.thinking).cue == .thought)
        #expect(AvatarVisual.of(.finished).face == .heureux)
    }

    @Test func reduceMotionGivesOneStillFrame() {
        for pose in PebbleAvatar.Pose.allCases {
            let a = AvatarMotion.of(pose, seconds: 1.3, reduced: true)
            let b = AvatarMotion.of(pose, seconds: 77, reduced: true)
            #expect(a.x == 0 && a.y == 0 && a.sx == 1 && a.sy == 1)
            #expect(a.tilt == (pose == .sleepy ? 8 : 0))
            #expect(a.tilt == b.tilt && a.pulse == b.pulse)
        }
        // under 0.5 Hz: the cue's pulse repeats every 2 s
        let p = AvatarMotion.of(.thinking, seconds: 0.3, reduced: false), q = AvatarMotion.of(.thinking, seconds: 2.3, reduced: false)
        #expect(abs(p.pulse.0 - q.pulse.0) < 1e-9)
    }

    @Test func theVeilKeepsPebblesTimings() {
        let on = AvatarVeil.at(on: true, dt: AvatarVeil.activate, reduced: false)
        #expect(on.cloak == 1 && on.rim == 1 && abs(on.glass - 1) < 1e-9 && on.eye == 0.8 && on.ping == -1)
        let gather = AvatarVeil.at(on: true, dt: 0.1, reduced: false)
        #expect(gather.cloak == 0 && gather.sy < 1 && gather.eye == 0)
        let off = AvatarVeil.at(on: false, dt: AvatarVeil.release, reduced: false)
        #expect(off.cloak == 0 && off.rim == 0 && off.glass == 0 && off.eye == 1)
        let fade = AvatarVeil.at(on: true, dt: 0.3, reduced: true)
        #expect(fade.fade && fade.cloak == 1 && fade.sy == 1 && fade.ping == -1)
        #expect(AvatarVeil.moving(on: true, dt: 1, reduced: false))
        #expect(!AvatarVeil.moving(on: true, dt: 1, reduced: true))
        #expect(AvatarVeil.shimmer(0.55) != nil && AvatarVeil.shimmer(2) == nil && AvatarVeil.shimmer(6.2) != nil)
        // reversing mid-cast starts from where it got to
        let mid = AvatarVeil.at(on: true, dt: 0.4, reduced: false)
        let back = AvatarVeil.at(on: false, dt: 0, from: mid, reduced: false)
        #expect(abs(back.cloak - mid.cloak) < 1e-9)
    }

    @Test func theScheduleSlowsWhenCalmAndStopsWhenStill() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let fast = AvatarSchedule(fastUntil: start.addingTimeInterval(1), still: false)
        let dates = Array(fast.entries(from: start, mode: .normal).prefix(40))
        #expect(abs(dates[1].timeIntervalSince(dates[0]) - 1.0 / 30) < 1e-9)
        #expect(abs(dates[39].timeIntervalSince(dates[38]) - 0.1) < 1e-9)
        let still = AvatarSchedule(fastUntil: .distantFuture, still: true)
        #expect(Array(still.entries(from: start, mode: .normal).prefix(5)).count == 1)
    }
}

struct AnnouncerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func oneSentencePerWindowAndTheLatestWins() {
        var a = StatusAnnouncer()
        #expect(a.say("Pebble is thinking", at: t0) == "Pebble is thinking")
        #expect(a.say("Pebble is reading", at: t0.addingTimeInterval(2)) == nil)
        #expect(a.say("Pebble is editing", at: t0.addingTimeInterval(3)) == nil)
        #expect(a.due == t0.addingTimeInterval(10))
        #expect(a.fire(at: t0.addingTimeInterval(9)) == nil)
        #expect(a.fire(at: t0.addingTimeInterval(10)) == "Pebble is editing")
        #expect(a.due == nil)
    }

    @Test func aChangeAndItsReversalSayNothing() {
        var a = StatusAnnouncer()
        _ = a.say("Pebble is thinking", at: t0)
        _ = a.say("Pebble is reading", at: t0.addingTimeInterval(1))
        #expect(a.say("Pebble is thinking", at: t0.addingTimeInterval(2)) == nil)
        #expect(a.due == nil)
    }

    @Test func replyFinishedIsSaidAtOnceAndDropsWhatWaits() {
        var a = StatusAnnouncer()
        _ = a.say("Pebble is thinking", at: t0)
        _ = a.say("Pebble is writing a reply", at: t0.addingTimeInterval(1))
        #expect(a.now(StatusCopy.finishedLabel, at: t0.addingTimeInterval(2)) == "Reply finished")
        #expect(a.due == nil)
        #expect(a.now(StatusCopy.finishedLabel, at: t0.addingTimeInterval(3)) == nil)
        a.clear()
        #expect(a.say("Pebble is thinking", at: t0.addingTimeInterval(20)) == "Pebble is thinking")
    }
}

import PebbleProtocol
import SwiftUI

/// Pebble's companion, the pebble with two capsule eyes, ported from Pebble's Avatar.vue and its engine.
///
/// - The pose comes from Pebble's own status (`Pose(status:)`), never from elapsed time.
/// - `stealth`: Stealth Lockdown's Veil (dusk colour, glass, rim), cast and released as on the Mac.
/// - `animated`: animate only the one avatar the person is looking at (the Pebble tab, the live run bar); every other
///   avatar (list rows, small badges) is a still frame. Under Reduce Motion every avatar is still.
/// - Calm poses (idle, waiting, finished, problems) settle after 8 s to slow life: blinks and drift at 10 frames a
///   second. Busy poses move at up to 30.
/// - `look`: a direction (x right, y down, each -1...1) the eyes turn toward, as the Mac's companion follows its pointer
///   (`PebbleTouchAvatar` passes the finger's); nil returns them to the pose's own.
/// - Decorative for VoiceOver: the words next to it (a status line, a title) carry the meaning.
///
/// Size it with `.frame(width:height:)`; it keeps a square aspect. Below 64 points it drops the glass detail and
/// thickens the Veil's rim, as on the Mac.
public struct PebbleAvatar: View {
    let pose: Pose
    let stealth: Bool
    let animated: Bool
    let look: CGVector?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var timeline = AvatarTimeline()

    public init(pose: Pose = .idle, stealth: Bool = false, animated: Bool = true, look: CGVector? = nil) {
        self.pose = pose
        self.stealth = stealth
        self.animated = animated
        self.look = look
    }

    /// The pose for one of Pebble's status keys (nil: resting).
    public init(status: StatusKey?, stealth: Bool = false, animated: Bool = true) {
        self.init(pose: Pose(status: status), stealth: stealth, animated: animated)
    }

    private var still: Bool { !animated || reduceMotion || scenePhase == .background }

    public var body: some View {
        let schedule = AvatarSchedule(
            fastUntil: timeline.fastUntil(pose: pose, stealth: stealth), still: still)
        TimelineView(schedule) { context in
            Canvas { graphics, size in
                AvatarRenderer.draw(
                    timeline.frame(pose: pose, stealth: stealth, at: context.date, still: still, reduceMotion: reduceMotion),
                    in: &graphics, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { timeline.begin(pose: pose, stealth: stealth) }
        .onChange(of: pose) { old, new in
            timeline.change(from: old, to: new, at: .now, still: still)
        }
        .onChange(of: stealth) { old, new in
            timeline.veil(from: old, to: new, at: .now, reduced: reduceMotion || !animated)
        }
        .onChange(of: look) { _, new in
            timeline.look(to: new.map(AvatarLook.toward) ?? .none, at: .now)
        }
    }
}

/// When the avatar's last changes happened, so a frame can blend from where the pebble was.
nonisolated struct AvatarTimeline {
    var start = Date()
    var pose: PebbleAvatar.Pose?
    var fromFace = FaceExpression.neutre
    var changedAt = Date.distantPast
    var blinkAt = Date.distantPast
    var dotSince = Date.distantPast
    var veilFrom = AvatarVeil.off
    var veilOn = false
    var veilChangedAt = Date.distantPast
    var lookFrom = AvatarLook.none
    var lookTo = AvatarLook.none
    var lookChangedAt = Date.distantPast

    /// How long a face takes to change (the engine's `SHAPE_MORPH`).
    static let morph = 0.45

    mutating func begin(pose: PebbleAvatar.Pose, stealth: Bool) {
        guard self.pose == nil else { return }
        start = .now
        self.pose = pose
        fromFace = AvatarVisual.of(pose).face
        veilOn = stealth
        veilFrom = stealth ? .on : .off
    }

    mutating func change(from old: PebbleAvatar.Pose, to new: PebbleAvatar.Pose, at now: Date, still: Bool) {
        fromFace = still ? AvatarVisual.of(new).face : face(for: old, at: now)
        changedAt = now
        pose = new
        let wasDot = AvatarVisual.of(old).dot, isDot = AvatarVisual.of(new).dot
        if isDot && !wasDot {
            blinkAt = now
            dotSince = now
        }
    }

    mutating func veil(from old: Bool, to new: Bool, at now: Date, reduced: Bool) {
        veilFrom = veilState(on: old, at: now, reduced: reduced)
        veilOn = new
        veilChangedAt = now
    }

    /// The eyes take a new direction, catching up from where they look now.
    mutating func look(to new: AvatarLook, at now: Date) {
        lookFrom = look(at: now)
        lookTo = new
        lookChangedAt = now
    }

    /// Where the eyes look at `now`, the catch-up included (engine.ts `lookAtTime`).
    func look(at now: Date) -> AvatarLook {
        let k = now.timeIntervalSince(lookChangedAt) / AvatarLook.morph
        guard k < 1 else { return lookTo }
        return .lerp(lookFrom, lookTo, AvatarFace.easeOutQuint(k))
    }

    /// The face shown at `now` while blending into `target`'s.
    func face(for target: PebbleAvatar.Pose, at now: Date) -> FaceExpression {
        let to = AvatarVisual.of(target).face
        let k = now.timeIntervalSince(changedAt) / Self.morph
        guard k < 1 else { return to }
        return .lerp(fromFace, to, AvatarFace.easeOutQuint(k))
    }

    func veilState(on: Bool, at now: Date, reduced: Bool) -> AvatarVeil {
        guard veilChangedAt != .distantPast else { return on ? .on : .off }
        return AvatarVeil.at(on: on, dt: now.timeIntervalSince(veilChangedAt), from: veilFrom, reduced: reduced)
    }

    /// Fast frames until a busy pose settles or a change has finished moving.
    func fastUntil(pose: PebbleAvatar.Pose, stealth: Bool) -> Date {
        if !pose.holds { return .distantFuture }
        let until = max(changedAt, start).addingTimeInterval(PebbleMotion.avatarHold)
        let looked = lookChangedAt.addingTimeInterval(AvatarLook.morph + 0.1)
        return max(until, veilChangedAt.addingTimeInterval(AvatarVeil.activate + 0.1), looked)
    }

    func frame(pose: PebbleAvatar.Pose, stealth: Bool, at now: Date, still: Bool, reduceMotion: Bool) -> AvatarFrame {
        let seconds = max(0, now.timeIntervalSince(start))
        // `onChange` lands after the first frame of a new pose: draw that frame without blending.
        let settled = self.pose != pose
        let face = still || settled ? AvatarVisual.of(pose).face : self.face(for: pose, at: now)
        let veilReduced = reduceMotion || still
        var veil = stealth == veilOn ? veilState(on: stealth, at: now, reduced: veilReduced) : (stealth ? .on : .off)
        if still { veil = stealth ? .on : .off }
        var shine: (Double, Double)?
        // The shimmer plays only while the avatar moves at full rate (a calm pose stops it after its hold, as on the Mac).
        if stealth && !still && now < fastUntil(pose: pose, stealth: stealth) {
            let since = veilChangedAt == .distantPast ? seconds : now.timeIntervalSince(veilChangedAt) - 0.95
            shine = AvatarVeil.shimmer(since).map { ($0.x, $0.opacity) }
        }
        return AvatarFrame(
            pose: pose, face: face, seconds: seconds, still: still,
            forcedBlink: settled ? nil : now.timeIntervalSince(blinkAt),
            dotAge: settled ? nil : now.timeIntervalSince(dotSince),
            veil: veil, shine: shine, look: still ? .none : look(at: now))
    }
}

/// Frames at 30 a second while something moves, then 10 a second (blinks and drift), and a single frame when still.
nonisolated struct AvatarSchedule: TimelineSchedule {
    var fastUntil: Date
    var still: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        if still {
            var sent = false
            return AnyIterator {
                defer { sent = true }
                return sent ? nil : startDate
            }
        }
        var next = startDate
        let fastUntil = fastUntil
        let slowStep = mode == .lowFrequency ? 1.0 : 0.1
        return AnyIterator {
            let current = next
            let fast = mode != .lowFrequency && current < fastUntil
            next = current.addingTimeInterval(fast ? 1.0 / 30 : slowStep)
            return current
        }
    }
}

#if os(iOS)
#Preview("Poses") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))]) {
            ForEach(PebbleAvatar.Pose.allCases, id: \.self) { pose in
                VStack {
                    PebbleAvatar(pose: pose)
                        .frame(width: 88, height: 88)
                    Text(pose.rawValue).font(PebbleFont.meta).foregroundStyle(PebbleColor.secondaryText)
                }
            }
        }
        .padding()
    }
}

#Preview("Stealth Veil") {
    @Previewable @State var stealth = false
    VStack(spacing: PebbleSpace.s5) {
        PebbleAvatar(pose: .idle, stealth: stealth)
            .frame(width: PebbleSize.avatarHero, height: PebbleSize.avatarHero)
        PebbleAvatar(pose: .thinking, stealth: stealth)
            .frame(width: PebbleSize.avatarInline, height: PebbleSize.avatarInline)
        Toggle(AppCopy.Stealth.name, isOn: $stealth)
            .padding()
    }
}
#endif

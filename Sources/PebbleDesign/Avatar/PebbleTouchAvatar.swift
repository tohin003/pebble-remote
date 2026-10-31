import SwiftUI

/// Pebble's avatar answering a touch, as the Mac's companion answers its pointer (the person, 2026-10-31: "put the
/// pebble's animated avatar with some interactive expressions triggered when touched like in the macs companion").
/// Pebble's own rules (Pet.vue; companionState.ts rows 13 and 16; companionPointer.ts):
/// - a finger held on the pebble makes it attentive (`hover`), and its eyes follow the finger;
/// - a tap makes it happy for a moment (`tap`, 1.2 s, Pebble's `TAP_MS`), with a little hop and a light tap of the
///   haptics;
/// - three taps in quick succession make it celebrate: Pebble's happy row, with its bounce and sparkles;
/// - while Pebble works or waits for the person, a touch only turns its eyes: the face never invents a mood while work is
///   under way (F1), so it never hides what Pebble is doing.
///
/// `reactions` and `followsFinger` are the Mac companion's own switches (Pebble's Settings › Appearance: Reactions,
/// Follow the pointer; Pebble's Reduce Motion turns both off). Under the iPhone's Reduce Motion the pebble stays still,
/// as every avatar does. Decorative for VoiceOver, like every avatar: a touch changes nothing but its face.
public struct PebbleTouchAvatar: View {
    let pose: PebbleAvatar.Pose
    let stealth: Bool
    let reactions: Bool
    let followsFinger: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the finger is on the pebble once it has been held there a moment, while it stays down. Only a hold
    /// follows the finger: a swipe that merely starts on the pebble scrolls the list and closes its keyboard, as
    /// anywhere else (a drag that took every touch kept Ask Pebble's keyboard up in the 15:00 device run).
    @GestureState private var finger: CGPoint?
    /// The face a tap, or a burst of taps, shows until it ends.
    @State private var reaction: PebbleAvatar.Pose?
    /// Where the eyes still look after a tap while Pebble works (a glance), until it ends.
    @State private var glance: CGVector?
    @State private var ending: Task<Void, Never>?
    @State private var recentTaps: [Date] = []
    /// Counts taps that changed the face, for the haptic; `celebrated` says which kind the last one was.
    @State private var reactionCount = 0
    @State private var celebrated = false
    @State private var size = CGSize.zero

    /// How long a tap's happy face holds (companionState.ts `TAP_MS`).
    public static let tapHold = 1.2
    /// How long the celebration holds.
    public static let celebrationHold = 2.6
    /// Taps this close together, three of them, are a burst.
    public static let burstWindow = 1.4
    /// How long a glance holds while Pebble works.
    static let glanceHold = 1.0

    public init(pose: PebbleAvatar.Pose, stealth: Bool = false, reactions: Bool = true, followsFinger: Bool = true) {
        self.pose = pose
        self.stealth = stealth
        self.reactions = reactions
        self.followsFinger = followsFinger
    }

    public var body: some View {
        PebbleAvatar(pose: shownPose, stealth: stealth, look: look)
            // A press gives a little, as a soft thing does; a tap springs back.
            .scaleEffect(finger != nil && !reduceMotion ? 0.93 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.5), value: finger != nil)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .contentShape(.circle)
            .simultaneousGesture(touch)
            .sensoryFeedback(trigger: reactionCount) { _, _ in
                celebrated ? SensoryFeedback.success : SensoryFeedback.impact(weight: .light, intensity: 0.7)
            }
            .onChange(of: pose) {
                // Pebble's own state wins at once: a run starting ends any reaction.
                if !rests { endReaction() }
            }
            .onDisappear { endReaction() }
    }

    /// Pebble rests (nothing running, nothing waiting): only then does a touch change its face.
    private var rests: Bool { pose == .idle || pose == .sleepy }

    private var reacts: Bool { reactions && rests && !reduceMotion }

    /// The reaction or the finger's attention over a resting pose; Pebble's own pose otherwise.
    private var shownPose: PebbleAvatar.Pose {
        guard reacts else { return pose }
        if let reaction { return reaction }
        if finger != nil { return .hover }
        return pose
    }

    /// The finger's direction while it is down, then a glance's; nil lets the eyes rest.
    private var look: CGVector? {
        guard followsFinger, !reduceMotion else { return nil }
        if let finger { return direction(to: finger) }
        return glance
    }

    /// A tap, or a hold that then follows the finger. A touch that moves before the hold fails both, so the list
    /// underneath scrolls.
    private var touch: some Gesture {
        let hold = LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($finger) { value, state, _ in
                if case .second(true, let drag?) = value { state = drag.location }
            }
        return SpatialTapGesture()
            .onEnded { value in tapped(at: value.location) }
            .exclusively(before: hold)
    }

    /// From the pebble's centre to the finger, reaching full turn at the pebble's rim.
    private func direction(to point: CGPoint) -> CGVector {
        let reach = min(size.width, size.height) * 0.55
        guard reach > 0 else { return .zero }
        return CGVector(
            dx: min(max((point.x - size.width / 2) / reach, -1), 1),
            dy: min(max((point.y - size.height / 2) / reach, -1), 1))
    }

    private func tapped(at point: CGPoint) {
        if reacts {
            let now = Date.now
            recentTaps = recentTaps.filter { now.timeIntervalSince($0) < Self.burstWindow } + [now]
            celebrated = recentTaps.count >= 3
            if celebrated { recentTaps = [] }
            reactionCount += 1
            hold(celebrated ? .finished : .tap, glance: nil, for: celebrated ? Self.celebrationHold : Self.tapHold)
        } else if followsFinger, !reduceMotion {
            hold(nil, glance: direction(to: point), for: Self.glanceHold)
        }
    }

    private func hold(_ face: PebbleAvatar.Pose?, glance: CGVector?, for seconds: Double) {
        reaction = face
        self.glance = glance
        ending?.cancel()
        ending = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            reaction = nil
            self.glance = nil
        }
    }

    private func endReaction() {
        ending?.cancel()
        ending = nil
        reaction = nil
        glance = nil
    }
}

#if os(iOS)
#Preview("Touch the pebble: resting, then working") {
    VStack(spacing: PebbleSpace.s5) {
        PebbleTouchAvatar(pose: .idle)
            .frame(width: 120, height: 120)
        PebbleTouchAvatar(pose: .thinking)
            .frame(width: 120, height: 120)
    }
}
#endif

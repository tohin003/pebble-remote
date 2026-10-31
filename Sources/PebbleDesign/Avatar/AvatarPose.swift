import PebbleProtocol

extension PebbleAvatar {
    /// What the pebble shows. One pose per row of Pebble's companion table (src/companionState.ts `POSES`); the
    /// status keys map onto them with `init(status:)`. Poses are chosen from what Pebble reports, never from elapsed
    /// time while work is under way.
    nonisolated public enum Pose: String, Sendable, Hashable, CaseIterable {
        /// Nothing running: the resting face, blinking now and then.
        case idle
        /// A long quiet spell (Pebble: no run and no input for 10 minutes).
        case sleepy
        /// Your message is on its way, until Pebble admits the run.
        case sending
        case thinking, writing, reading, searching, editing, testing, running, delegating, viewing, working, loading
        case reconnecting
        /// Pebble waits for your answer: the notification dot and wide eyes.
        case question
        /// An action waits for your review.
        case review
        case paused
        case blocked
        case uncertain
        case offline
        /// The run hit a problem.
        case problem
        /// The reply finished (a short celebration on the desktop; here it holds while shown).
        case finished
        case stopped
        /// Something new to look at, with no run waiting.
        case notify
        /// A finger on the resting pebble (the Mac's pointer over the companion, row 16): attentive, leaning in.
        case hover
        /// Just touched (the Mac's click on the companion, row 16): happy for a moment, with a little hop.
        case tap

        /// The pose for one of Pebble's status keys; nil is the resting pose.
        public init(status: StatusKey?) {
            switch status {
            case nil: self = .idle
            case .thinking?: self = .thinking
            case .writing?: self = .writing
            case .reading?: self = .reading
            case .searching?: self = .searching
            case .editing?: self = .editing
            case .testing?: self = .testing
            case .running?: self = .running
            case .delegating?: self = .delegating
            case .viewing?: self = .viewing
            case .working?: self = .working
            case .loading?: self = .loading
            case .question?: self = .question
            case .review?: self = .review
            case .reconnecting?: self = .reconnecting
            case .blocked?: self = .blocked
            case .uncertain?: self = .uncertain
            case .offline?: self = .offline
            case .paused?: self = .paused
            case .error?: self = .problem
            case .sending?: self = .sending
            }
        }

        /// The status key this pose shows, if it has one.
        public var status: StatusKey? {
            switch self {
            case .thinking: .thinking
            case .writing: .writing
            case .reading: .reading
            case .searching: .searching
            case .editing: .editing
            case .testing: .testing
            case .running: .running
            case .delegating: .delegating
            case .viewing: .viewing
            case .working: .working
            case .loading: .loading
            case .question: .question
            case .review: .review
            case .reconnecting: .reconnecting
            case .blocked: .blocked
            case .uncertain: .uncertain
            case .offline: .offline
            case .paused: .paused
            case .problem: .error
            case .sending: .sending
            case .idle, .sleepy, .finished, .stopped, .notify, .hover, .tap: nil
            }
        }

        /// Calm poses settle to a still frame after `PebbleMotion.avatarHold` (then only blink).
        var holds: Bool {
            switch self {
            case .idle, .sleepy, .question, .review, .paused, .blocked, .uncertain, .offline, .problem, .finished,
                .stopped, .notify, .hover, .tap:
                true
            default:
                false
            }
        }
    }
}

/// How a pose looks: the face, whether the notification dot shows, and the cue drawn above the pebble.
nonisolated struct AvatarVisual {
    enum Cue: Equatable { case none, thought, orbit, scan, spark, celebrate, attention, sleep, sigh }

    var face: FaceExpression
    var dot: Bool
    var cue: Cue

    static func of(_ pose: PebbleAvatar.Pose) -> AvatarVisual {
        switch pose {
        case .offline: AvatarVisual(face: .triste, dot: false, cue: .none)
        case .uncertain: AvatarVisual(face: .mefiant, dot: false, cue: .attention)
        case .problem: AvatarVisual(face: .triste, dot: false, cue: .sigh)
        case .review: AvatarVisual(face: .attentif, dot: false, cue: .attention)
        case .question: AvatarVisual(face: .notify, dot: true, cue: .none)
        case .reconnecting: AvatarVisual(face: .attentif, dot: false, cue: .orbit)
        case .blocked: AvatarVisual(face: .confus, dot: false, cue: .none)
        case .sending: AvatarVisual(face: .attentif, dot: false, cue: .none)
        case .reading: AvatarVisual(face: .attentif, dot: false, cue: .scan)
        case .searching: AvatarVisual(face: .curieux, dot: false, cue: .scan)
        case .editing: AvatarVisual(face: .fier, dot: false, cue: .spark)
        case .testing: AvatarVisual(face: .mefiant, dot: false, cue: .orbit)
        case .running: AvatarVisual(face: .attentif, dot: false, cue: .orbit)
        case .delegating: AvatarVisual(face: .curieux, dot: false, cue: .thought)
        case .viewing: AvatarVisual(face: .fier, dot: false, cue: .spark)
        case .working: AvatarVisual(face: .attentif, dot: false, cue: .thought)
        case .writing: AvatarVisual(face: .fier, dot: false, cue: .none)
        case .loading: AvatarVisual(face: .attentif, dot: false, cue: .orbit)
        case .thinking: AvatarVisual(face: .curieux, dot: false, cue: .thought)
        case .paused: AvatarVisual(face: .blase, dot: false, cue: .none)
        case .finished: AvatarVisual(face: .heureux, dot: false, cue: .celebrate)
        case .stopped: AvatarVisual(face: .blase, dot: false, cue: .none)
        case .notify: AvatarVisual(face: .notify, dot: true, cue: .none)
        case .sleepy: AvatarVisual(face: .somnolent, dot: false, cue: .sleep)
        case .idle: AvatarVisual(face: .neutre, dot: false, cue: .none)
        case .hover: AvatarVisual(face: .attentif, dot: false, cue: .none)
        case .tap: AvatarVisual(face: .heureux, dot: false, cue: .none)
        }
    }
}

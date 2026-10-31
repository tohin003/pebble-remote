import SwiftUI

/// What each moment feels like, for `.sensoryFeedback(_:trigger:)`. Haptics confirm what the person did or tell
/// them Pebble needs them; they never decorate progress. One haptic per event, never one per streamed token.
///
/// ```swift
/// .sensoryFeedback(PebbleHaptics.approved, trigger: approvedCount)
/// ```
nonisolated public enum PebbleHaptics {
    /// An approval went through (after Face ID and Pebble's answer, not on the tap).
    public static let approved: SensoryFeedback = .success
    /// A card was rejected, or a question dismissed.
    public static let rejected: SensoryFeedback = .impact(weight: .light)
    /// A run was stopped, paused or resumed.
    public static let stopped: SensoryFeedback = .impact(weight: .medium)
    /// "Stop everything" went through.
    public static let stoppedEverything: SensoryFeedback = .warning
    /// Something new needs the person (the first waiting card or question), while the app is open.
    public static let needsYou: SensoryFeedback = .warning
    /// Pebble refused, or a call failed.
    public static let problem: SensoryFeedback = .error
    /// A reply finished while the person watched the conversation.
    public static let finished: SensoryFeedback = .impact(flexibility: .soft, intensity: 0.6)
    /// A message or guidance was sent.
    public static let sent: SensoryFeedback = .impact(flexibility: .soft, intensity: 0.5)
    /// A choice changed: mode, Fast replies, an option in a question.
    public static let selection: SensoryFeedback = .selection
    /// Connected to the Mac after being away (not on every reconnect attempt).
    public static let connected: SensoryFeedback = .impact(flexibility: .soft, intensity: 0.4)
}

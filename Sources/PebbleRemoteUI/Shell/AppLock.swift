import Foundation
import LocalAuthentication
import Observation
import PebbleDesign

/// The app lock: Face ID (or the passcode) when the app opens and whenever it comes back from the background.
/// On by default; the person turns it off in Settings. It applies only while a Mac is paired, never in the demo.
///
/// It locks on `.background` only, never on `.inactive`: Face ID's own prompt (for unlocking, or for an approval)
/// makes the scene inactive, and locking then would hide the screen the person is approving from.
@Observable
final class AppLock {
    /// The Settings switch ("Unlock with Face ID"), in UserDefaults so @AppStorage can bind to it.
    static let settingKey = "unlockWithFaceID"

    private(set) var isLocked = false
    private(set) var isUnlocking = false
    /// Why the last try failed, shown on the lock screen; nil after a cancel.
    private(set) var problem: String?
    /// One automatic Face ID prompt per return to the app; after a cancel the person taps Unlock.
    @ObservationIgnored private var triedThisVisit = false
    /// Set by the app's model (C1): unlocks the bridge, whose Face ID check then also lifts this lock, so one Face ID
    /// covers both. Returns nil when it can't (not connected, or the bridge has no unlock): the device's own check
    /// runs instead. True: unlocked. False: the person cancelled.
    @ObservationIgnored var unlockWithBridge: (() async -> Bool?)?
    /// Set by the app's model (S-05): called each time the lock engages, so the Mac's unlock ends with it instead of
    /// outliving the app's use.
    @ObservationIgnored var onLocked: (() -> Void)?

    /// The person's setting; on unless they turned it off.
    static var isWanted: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Locks when the setting is on and the lock applies (a Mac is paired, not the demo), and says so (`onLocked`).
    func lock(applies: Bool) {
        guard applies, Self.isWanted else { return }
        isLocked = true
        problem = nil
        onLocked?()
    }

    /// Lifts the lock without asking: the lock no longer applies (the Mac was forgotten, the demo started).
    func release() {
        isLocked = false
        problem = nil
    }

    func sceneEnteredBackground(applies: Bool) {
        triedThisVisit = false
        lock(applies: applies)
    }

    /// Asks once, automatically, each time the app comes back while locked.
    func sceneBecameActive() {
        guard isLocked, !triedThisVisit else { return }
        triedThisVisit = true
        Task { await unlock() }
    }

    func unlock() async {
        guard isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        if let unlockWithBridge, let unlocked = await unlockWithBridge() {
            if unlocked { isLocked = false }
            problem = nil
            return
        }
        switch await Self.authenticate(reason: AppCopy.FaceID.lockReason) {
        case .success, .unavailable:
            isLocked = false
            problem = nil
        case .cancelled:
            problem = nil
        case .failed:
            problem = AppCopy.FaceID.lockFailed
        }
    }

    enum Outcome: Equatable {
        case success
        case cancelled
        /// The device has no passcode, so there is nothing to check against; the lock cannot apply.
        case unavailable
        case failed
    }

    /// Face ID, Touch ID or the device passcode.
    static func authenticate(reason: String) async -> Outcome {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return outcomeWhenUnavailable(error)
        }
        do {
            let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return passed ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: return .cancelled
            case .passcodeNotSet: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Why the check could not run decides whether the lock lifts. Only a phone without a passcode has nothing to
    /// check against; any other reason (an error this version does not know, a check that cannot run now) keeps the
    /// lock and lets the person try again (security review 2026-10-30, S-09).
    static func outcomeWhenUnavailable(_ error: NSError?) -> Outcome {
        guard let error, error.domain == LAErrorDomain, error.code == LAError.Code.passcodeNotSet.rawValue else {
            return .failed
        }
        return .unavailable
    }
}

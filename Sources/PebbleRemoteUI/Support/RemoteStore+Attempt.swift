import PebbleProtocol
import PebbleRemoteKit

extension RemoteStore {
    /// Runs a call the person asked for. When it fails, the store has already set `notice` in Pebble's or the bridge's
    /// words (nothing for a cancelled Face ID), and the root shows it once; the result only tells the caller whether to
    /// put back what it cleared (a draft, a switch).
    @discardableResult
    func attempt(_ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            return true
        } catch {
            return false
        }
    }

    /// The same, for a call with a result: the result, or nil when it failed.
    func attempt<Value>(_ work: () async throws -> Value) async -> Value? {
        try? await work()
    }

    /// Whether the connected bridge accepts `method`. Before the first welcome nothing is known, so controls show (and
    /// calls wait for the connection); once connected, what the bridge doesn't offer is hidden.
    func bridgeOffers(_ method: String) -> Bool {
        bridge?.methods.contains(method) ?? true
    }

    /// The failure a call just left in `notice`, taken to show where the person is: inside a sheet, as Pebble's own
    /// dialogs show theirs, instead of the root's alert under the sheet. Nil when there was none (Face ID cancelled).
    func takeNotice() -> String? {
        guard let failure = notice else { return nil }
        notice = nil
        return failure.message
    }

    /// For `alert(isPresented:)`: true while a notice waits; setting false clears it. An `unlock_required` refusal
    /// opens the unlock sheet instead of the alert.
    var isShowingNotice: Bool {
        get { notice != nil && notice?.code != Self.unlockRequiredCode }
        set { if !newValue { notice = nil } }
    }

    var isConnectedToMac: Bool {
        if case .connected = connection.phase { true } else { false }
    }

    /// The bridge asks for an unlock before Pebble acts (C1): its welcome said how long one lasts.
    var usesUnlock: Bool { bridge?.unlockSeconds != nil }

    /// How long an unlock lasts, in minutes (the bridge's `unlock_seconds`; 15 unless the person changed it on the Mac).
    var unlockMinutes: Int { max(1, (bridge?.unlockSeconds ?? RemoteContract.defaultUnlockSeconds) / 60) }

    /// The bridge refused a call until the person unlocks (after the client's own Face ID retry).
    static let unlockRequiredCode = "unlock_required"
}

import Foundation

extension RemoteStore {
    // MARK: Ending the unlock (contract S-05)

    /// Ends this phone's unlock on the Mac now: the app goes to the background, or its own lock engages. The unlock
    /// should end when the phone stops using it, not when its time runs out, so that nobody who picks up the phone
    /// meanwhile finds Pebble ready to act.
    ///
    /// `unlockedUntil` is cleared first, so the screens never claim an unlock that is ending. Then the client asks the
    /// Mac to end it too (`remote.lock`), if the Mac offers that: briefly, and ignoring failure, because the Mac also
    /// ends a device's unlock when its last connection closes. A Mac that does not offer it keeps its old behaviour.
    /// Callers that arrive while the call is under way share it.
    public func lock() async {
        unlockedUntil = nil
        if let locking { return await locking.value }
        let client = self.client
        let task = Task { await client.lock() }
        locking = task
        await task.value
        locking = nil
    }
}

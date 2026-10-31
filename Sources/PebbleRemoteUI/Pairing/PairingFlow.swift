import Observation
import PebbleDesign
import PebbleRemoteKit

/// One pairing attempt at a time, from a pasted, scanned, typed or opened link. Errors stay on the pairing screen
/// (inline): the store's notice for the failure moves here instead of the app-wide alert.
///
/// Once the phone has sent its signatures, the flow holds `code`: the six digits the person compares with the Mac's
/// before confirming there (X-1). The Mac gives them two minutes, so the wait is long and the person can `cancel()`
/// it. A pairing that the Mac does not confirm ends as `problem` in words that say what to do (`PairingWords`).
@Observable
final class PairingFlow {
    private(set) var isPairing = false
    /// The code to compare with the Mac's while the Mac waits for the person to confirm; nil otherwise.
    private(set) var code: PairingCode?
    /// What went wrong last, in Pebble's words; cleared by the next attempt.
    var problem: String?

    @ObservationIgnored private var attempt: Task<Void, any Error>?
    @ObservationIgnored private var attemptNumber = 0

    /// Pairs from text the person pasted, typed or scanned.
    func pair(text: String, model: PebbleRemoteModel) async {
        guard let link = PairingLink(string: text) else {
            problem = AppCopy.Pairing.notALink
            return
        }
        await pair(link, model: model)
    }

    func pair(_ link: PairingLink, model: PebbleRemoteModel) async {
        guard !isPairing else { return }
        isPairing = true
        problem = nil
        code = nil
        attemptNumber += 1
        let number = attemptNumber
        defer {
            isPairing = false
            code = nil
            attempt = nil
        }
        // The code comes from the client's task; it is shown on the main actor.
        let shown: @Sendable (PairingCode) -> Void = { [weak self] code in
            Task { @MainActor in await self?.show(code, attempt: number) }
        }
        let work = Task {
            try await model.pair(using: link, deviceName: DeviceName.current, showingCode: shown)
        }
        attempt = work
        do {
            try await work.value
        } catch {
            problem = PairingWords.message(for: error) ?? model.store.notice?.message
            model.store.notice = nil
        }
    }

    /// The person leaves the wait for the Mac. Nothing is kept, and the link is spent: the next pairing needs a new one.
    func cancel() {
        attempt?.cancel()
    }

    /// How long the code waits before it shows. The phone cannot tell a link the Mac refuses (used, expired) from one it
    /// accepts until the answer comes, and that answer comes within a few hundred milliseconds: after a moment's
    /// grace the code is shown only for a pairing that is still waiting, and a refused link never flashes one.
    static let grace = Duration.milliseconds(300)

    /// The code arrives from the client's task; a late one from an attempt that is over is dropped.
    private func show(_ code: PairingCode, attempt number: Int) async {
        try? await Task.sleep(for: Self.grace)
        guard isPairing, number == attemptNumber else { return }
        self.code = code
    }
}

import Foundation
import PebbleProtocol
import PebbleRemoteKit
import Synchronization

/// A client for the shell's tests (lane X): it records what the store asks of it, and a pairing waits until the test
/// plays the Mac's person: confirming on the Mac, or cancelling there.
nonisolated final class ShellProbeClient: RemoteClient {
    let updates: AsyncStream<ClientUpdate>
    private let sink: AsyncStream<ClientUpdate>.Continuation
    private let log = Mutex<[String]>([])
    private let outcome = Mutex<Result<PairedMac, RemoteCallError>?>(nil)
    private let code: PairingCode

    /// `code` is the six digits the client reports once its pairing has gone out.
    init(code: String = "035072") {
        (updates, sink) = AsyncStream.makeStream(of: ClientUpdate.self)
        self.code = PairingCode(digits: code) ?? PairingCode(pairTranscript: Data())
    }

    /// What the store asked, in order: "connect", "disconnect", "lock", "pair", "pairing cancelled", "call <method>".
    var events: [String] { log.withLock { $0 } }

    /// The Mac's person confirms that the codes match: the waiting pairing returns `mac`.
    func macConfirms(_ mac: PairedMac) { outcome.withLock { $0 = .success(mac) } }
    /// The Mac's person cancels: the waiting pairing throws `bad_code`, as the bridge's `bye` does.
    func macCancels() { outcome.withLock { $0 = .failure(.transport("bad_code")) } }

    private func record(_ event: String) { log.withLock { $0.append(event) } }

    func connect(to mac: PairedMac) async { record("connect") }
    func disconnect() async { record("disconnect") }
    func lock() async { record("lock") }

    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        record("call \(method)")
        return .null
    }

    func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue {
        record("elevated \(method)")
        return .null
    }

    func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac {
        try await pair(link, deviceName: deviceName, showingCode: { _ in })
    }

    func pair(
        _ link: PairingLink, deviceName: String, showingCode: @escaping @Sendable (PairingCode) -> Void
    ) async throws -> PairedMac {
        record("pair")
        showingCode(code)
        while true {
            if let decided = outcome.withLock({ $0 }) { return try decided.get() }
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                record("pairing cancelled")
                throw RemoteCallError.cancelledByPerson
            }
        }
    }
}

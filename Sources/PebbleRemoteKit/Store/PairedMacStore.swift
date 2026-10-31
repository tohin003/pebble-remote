import Foundation
import Synchronization

/// Where the paired Mac is kept between launches: one Mac per phone in v1. RemoteStore saves it after pairing, loads it
/// at launch and removes it when the person forgets the Mac. Lane B implements the Keychain version (over its
/// `SecretStore`); tests, previews and the demo use `InMemoryPairedMacStore`.
public protocol PairedMacStore: Sendable {
    /// The paired Mac, or nil before pairing and after the person forgot it.
    func load() throws -> PairedMac?
    /// Replaces whatever was kept.
    func save(_ mac: PairedMac) throws
    /// Forgets the Mac. Not an error when nothing was kept.
    func remove() throws
}

/// Keeps the paired Mac in memory only: tests, previews and the demo.
public final class InMemoryPairedMacStore: PairedMacStore {
    private let kept: Mutex<PairedMac?>

    public init(_ mac: PairedMac? = nil) {
        kept = Mutex(mac)
    }

    public func load() throws -> PairedMac? { kept.withLock { $0 } }
    public func save(_ mac: PairedMac) throws { kept.withLock { $0 = mac } }
    public func remove() throws { kept.withLock { $0 = nil } }
}

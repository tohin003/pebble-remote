import Foundation

/// The paired Mac kept in the Keychain (a this-device-only generic password holding the `PairedMac` as JSON), so it
/// survives launches and the weekly reinstall from Xcode but never leaves the phone. Lane A's `PairedMacStore`.
public struct KeychainPairedMacStore: PairedMacStore {
    static let account = "paired-mac"

    public let store: any SecretStore

    /// - Parameter store: the app's Keychain by default; tests pass `InMemorySecretStore`.
    public init(store: any SecretStore = KeychainSecretStore(service: "PebbleRemote.pairing")) {
        self.store = store
    }

    public func load() throws -> PairedMac? {
        guard let data = try store.read(Self.account) else { return nil }
        do {
            return try JSONDecoder().decode(PairedMac.self, from: data)
        } catch {
            throw RemoteKeyError.unreadableStoredKeys
        }
    }

    public func save(_ mac: PairedMac) throws {
        try store.write(try JSONEncoder().encode(mac), for: Self.account)
    }

    public func remove() throws {
        try store.delete(Self.account)
    }
}

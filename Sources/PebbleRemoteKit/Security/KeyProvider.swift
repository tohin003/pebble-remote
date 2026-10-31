import CryptoKit
import Foundation

/// The phone's two P-256 keys for one paired Mac (contract section 3.2).
public enum KeyRole: String, Sendable, Hashable, CaseIterable {
    /// No biometry. Signs every connection's challenge (T_hello) and the pairing (T_pair).
    case device
    /// Needs Face ID. Signs elevated calls (T_proof) and the pairing.
    case approve
}

/// One private key that signs. Signatures are DER ECDSA P-256 over SHA-256 of the message.
public protocol SigningKey: Sendable {
    var role: KeyRole { get }
    var publicKey: P256.Signing.PublicKey { get }
    /// Signs `message`. For the approve key, `reason` is the sentence Face ID shows ("Approve: run npm test"); a
    /// cancelled prompt throws `RemoteCallError.cancelledByPerson`.
    func sign(_ message: Data, reason: String) async throws -> Data
}

extension SigningKey {
    /// X9.63 uncompressed (65 bytes), as the contract sends public keys.
    public var publicKeyX963: Data { publicKey.x963Representation }
    /// The public key as it goes on the wire: base64url of X9.63.
    public var publicKeyText: String { Base64URL.encode(publicKey.x963Representation) }
}

/// The device and approve keys for one Mac.
public struct DeviceKeys: Sendable {
    public var device: any SigningKey
    public var approve: any SigningKey

    public init(device: any SigningKey, approve: any SigningKey) {
        self.device = device
        self.approve = approve
    }
}

/// Makes, keeps and finds the phone's keys. Keys are made in memory for a pairing and kept only once it succeeds, so
/// a failed re-pairing never destroys keys that still work.
public protocol KeyProvider: Sendable {
    /// Fresh keys for a new pairing; nothing is stored yet.
    func makeKeys() async throws -> DeviceKeys
    /// Keeps `keys` for this Mac, replacing any kept before.
    func save(_ keys: DeviceKeys, for bridgeID: String) async throws
    /// The keys kept for this Mac, or nil.
    func keys(for bridgeID: String) async throws -> DeviceKeys?
    func deleteKeys(for bridgeID: String) async throws
    /// Ends the window in which one Face ID check covers the next approvals (3.6: 30 s), so the next one asks again.
    /// Called when the unlock ends (S-05: the app went to the background, or its lock engaged; security review
    /// S-14). Providers whose keys never ask (software keys) use the default, which does nothing.
    func endApprovalWindow() async
}

extension KeyProvider {
    public func endApprovalWindow() async {}
}

/// How a key pair is kept in a `SecretStore`: one item per Mac, so both keys are saved or replaced together.
struct StoredKeyPair: Codable, Hashable {
    enum Kind: String, Codable { case software, secureEnclave }
    var kind: Kind
    /// Software: the raw private key. Secure Enclave: the key's `dataRepresentation`, a blob only this phone's
    /// Secure Enclave can use.
    var device: Data
    var approve: Data
    var devicePublic: Data
    var approvePublic: Data

    static func account(for bridgeID: String) -> String { "keys/\(bridgeID)" }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> StoredKeyPair {
        do {
            return try JSONDecoder().decode(StoredKeyPair.self, from: data)
        } catch {
            throw RemoteKeyError.unreadableStoredKeys
        }
    }
}

// MARK: - Software keys

/// A plain CryptoKit key in memory: tests, the demo, and the Mac (no Face ID). `sign` never prompts.
public struct SoftwareSigningKey: SigningKey {
    public let role: KeyRole
    public let privateKey: P256.Signing.PrivateKey

    public init(role: KeyRole, privateKey: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) {
        self.role = role
        self.privateKey = privateKey
    }

    public var publicKey: P256.Signing.PublicKey { privateKey.publicKey }

    public func sign(_ message: Data, reason: String) async throws -> Data {
        try privateKey.signature(for: message).derRepresentation
    }
}

/// Keys as plain CryptoKit keys, kept in a `SecretStore` (memory by default). For tests, the demo and the Mac.
public struct SoftwareKeyProvider: KeyProvider {
    public let store: any SecretStore

    public init(store: any SecretStore = InMemorySecretStore()) {
        self.store = store
    }

    public func makeKeys() async throws -> DeviceKeys {
        DeviceKeys(device: SoftwareSigningKey(role: .device), approve: SoftwareSigningKey(role: .approve))
    }

    public func save(_ keys: DeviceKeys, for bridgeID: String) async throws {
        guard let device = keys.device as? SoftwareSigningKey, let approve = keys.approve as? SoftwareSigningKey else {
            throw RemoteKeyError.foreignKey
        }
        let stored = StoredKeyPair(
            kind: .software, device: device.privateKey.rawRepresentation, approve: approve.privateKey.rawRepresentation,
            devicePublic: device.publicKeyX963, approvePublic: approve.publicKeyX963)
        try store.write(try stored.encoded(), for: StoredKeyPair.account(for: bridgeID))
    }

    public func keys(for bridgeID: String) async throws -> DeviceKeys? {
        guard let data = try store.read(StoredKeyPair.account(for: bridgeID)) else { return nil }
        let stored = try StoredKeyPair.decode(data)
        guard stored.kind == .software,
            let device = try? P256.Signing.PrivateKey(rawRepresentation: stored.device),
            let approve = try? P256.Signing.PrivateKey(rawRepresentation: stored.approve)
        else { throw RemoteKeyError.unreadableStoredKeys }
        return DeviceKeys(
            device: SoftwareSigningKey(role: .device, privateKey: device),
            approve: SoftwareSigningKey(role: .approve, privateKey: approve))
    }

    public func deleteKeys(for bridgeID: String) async throws {
        try store.delete(StoredKeyPair.account(for: bridgeID))
    }
}

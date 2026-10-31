import Foundation
import Security
import Synchronization

/// Small secrets kept by name: the pairing keys' stored form and the paired Macs. The app uses the Keychain; tests,
/// previews and the demo use memory (tests never touch the real Keychain).
public protocol SecretStore: Sendable {
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, for account: String) throws
    func delete(_ account: String) throws
}

/// What went wrong with a key or the Keychain. Content-free: safe to log.
public enum RemoteKeyError: Error, Sendable, Hashable {
    /// This device has no Secure Enclave (the simulator, an old Mac).
    case secureEnclaveUnavailable
    /// Face ID is not set up, is locked out, or the device has no passcode.
    case biometryUnavailable
    /// Face ID did not recognise the person.
    case notAuthenticated
    /// A Keychain call failed with this status.
    case keychain(OSStatus)
    /// The stored keys for this Mac could not be read back.
    case unreadableStoredKeys
    /// The keys were made by another provider and cannot be stored by this one.
    case foreignKey
    case signingFailed
}

/// Generic-password Keychain items under one service. Every item is this-device-only: never in backups or iCloud.
public struct KeychainSecretStore: SecretStore {
    public enum Accessibility: Sendable, Hashable {
        /// Readable once the phone has been unlocked after starting (connections in the background, later).
        case afterFirstUnlockThisDeviceOnly
        case whenUnlockedThisDeviceOnly

        var value: CFString {
            switch self {
            case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
        }
    }

    public var service: String
    public var accessibility: Accessibility

    public init(service: String, accessibility: Accessibility = .afterFirstUnlockThisDeviceOnly) {
        self.service = service
        self.accessibility = accessibility
    }

    public func read(_ account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw RemoteKeyError.keychain(status)
        }
    }

    public func write(_ data: Data, for account: String) throws {
        let query = baseQuery(account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility.value,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw RemoteKeyError.keychain(status) }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RemoteKeyError.keychain(status) }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // The iOS-style keychain on macOS too (the demo and tests on the Mac), never the legacy file keychain.
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

/// Secrets in memory only, for tests, previews and the demo.
public final class InMemorySecretStore: SecretStore {
    private let items = Mutex<[String: Data]>([:])

    public init(_ initial: [String: Data] = [:]) {
        items.withLock { $0 = initial }
    }

    public func read(_ account: String) throws -> Data? {
        items.withLock { $0[account] }
    }

    public func write(_ data: Data, for account: String) throws {
        items.withLock { $0[account] = data }
    }

    public func delete(_ account: String) throws {
        _ = items.withLock { $0.removeValue(forKey: account) }
    }

    /// Every account name kept, sorted (for tests).
    public var accounts: [String] {
        items.withLock { $0.keys.sorted() }
    }
}

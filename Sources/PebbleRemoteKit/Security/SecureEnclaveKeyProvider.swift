import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// The phone's keys in the Secure Enclave (contract section 3.2). The private keys never leave it: the Keychain keeps
/// only each key's `dataRepresentation`, a blob that only this phone's Secure Enclave can use, as a this-device-only
/// generic-password item.
///
/// - `device`: `.privateKeyUsage` only. Signs every connection's challenge without asking the person.
/// - `approve`: `.privateKeyUsage` and `.biometryCurrentSet`. Every signature asks for Face ID, showing the reason
///   given; one Face ID check covers the signatures of the next 30 s ("a burst of approvals asks once", 3.6), and
///   enrolling a new face makes the key unusable (pair again).
public struct SecureEnclaveKeyProvider: KeyProvider {
    public static var isAvailable: Bool { SecureEnclave.isAvailable }

    public let store: any SecretStore
    let gate: ApprovalGate

    /// - Parameter store: where the key blobs are kept; the app's Keychain by default.
    public init(store: any SecretStore = KeychainSecretStore(service: "PebbleRemote.keys")) {
        self.store = store
        self.gate = ApprovalGate()
    }

    public func makeKeys() async throws -> DeviceKeys {
        guard SecureEnclave.isAvailable else { throw RemoteKeyError.secureEnclaveUnavailable }
        guard
            let deviceAccess = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [.privateKeyUsage], nil),
            let approveAccess = SecAccessControlCreateWithFlags(
                nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], nil)
        else { throw RemoteKeyError.secureEnclaveUnavailable }
        let device: SecureEnclave.P256.Signing.PrivateKey
        let approve: SecureEnclave.P256.Signing.PrivateKey
        do {
            device = try SecureEnclave.P256.Signing.PrivateKey(accessControl: deviceAccess)
        } catch {
            throw RemoteKeyError.secureEnclaveUnavailable
        }
        do {
            approve = try SecureEnclave.P256.Signing.PrivateKey(accessControl: approveAccess)
        } catch {
            // No face enrolled (or no passcode): a biometry-bound key cannot be made.
            throw RemoteKeyError.biometryUnavailable
        }
        return DeviceKeys(
            device: EnclaveSigningKey(role: .device, blob: device.dataRepresentation, publicKey: device.publicKey, gate: nil),
            approve: EnclaveSigningKey(
                role: .approve, blob: approve.dataRepresentation, publicKey: approve.publicKey, gate: gate))
    }

    public func save(_ keys: DeviceKeys, for bridgeID: String) async throws {
        guard let device = keys.device as? EnclaveSigningKey, let approve = keys.approve as? EnclaveSigningKey else {
            throw RemoteKeyError.foreignKey
        }
        let stored = StoredKeyPair(
            kind: .secureEnclave, device: device.blob, approve: approve.blob, devicePublic: device.publicKeyX963,
            approvePublic: approve.publicKeyX963)
        try store.write(try stored.encoded(), for: StoredKeyPair.account(for: bridgeID))
    }

    public func keys(for bridgeID: String) async throws -> DeviceKeys? {
        guard let data = try store.read(StoredKeyPair.account(for: bridgeID)) else { return nil }
        let stored = try StoredKeyPair.decode(data)
        // The public keys are kept beside the blobs, so reading them back never touches the approve key (no Face ID).
        guard stored.kind == .secureEnclave,
            let devicePublic = try? P256.Signing.PublicKey(x963Representation: stored.devicePublic),
            let approvePublic = try? P256.Signing.PublicKey(x963Representation: stored.approvePublic)
        else { throw RemoteKeyError.unreadableStoredKeys }
        return DeviceKeys(
            device: EnclaveSigningKey(role: .device, blob: stored.device, publicKey: devicePublic, gate: nil),
            approve: EnclaveSigningKey(role: .approve, blob: stored.approve, publicKey: approvePublic, gate: gate))
    }

    public func deleteKeys(for bridgeID: String) async throws {
        try store.delete(StoredKeyPair.account(for: bridgeID))
    }

    /// The Face ID the person gave a moment ago no longer covers an approval: the next one asks (S-14).
    public func endApprovalWindow() async {
        await gate.endWindow()
    }
}

/// A Secure Enclave key, held as its blob. The approve key signs through the provider's `ApprovalGate` (Face ID).
struct EnclaveSigningKey: SigningKey {
    let role: KeyRole
    let blob: Data
    let publicKey: P256.Signing.PublicKey
    let gate: ApprovalGate?

    func sign(_ message: Data, reason: String) async throws -> Data {
        if let gate { return try await gate.sign(message, blob: blob, reason: reason) }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
            return try key.signature(for: message).derRepresentation
        } catch {
            throw RemoteKeyError.signingFailed
        }
    }
}

/// Face ID for the approve key. One successful check is reused for 30 s, so a burst of approvals asks once; callers
/// that arrive while a prompt is up wait for it instead of raising a second one.
actor ApprovalGate {
    /// How long one Face ID check covers further approvals (contract 3.6).
    static let reuseSeconds: TimeInterval = 30

    private var context: LAContext?
    private var authenticatedAt: ContinuousClock.Instant?
    private var authenticating = false
    private var waiters: [CheckedContinuation<Void, any Error>] = []

    func sign(_ message: Data, blob: Data, reason: String) async throws -> Data {
        let context = try await authenticatedContext(reason: reason)
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob, authenticationContext: context)
            return try key.signature(for: message).derRepresentation
        } catch {
            forget()
            throw Self.mapped(error)
        }
    }

    private func authenticatedContext(reason: String) async throws -> LAContext {
        while true {
            if let context, let authenticatedAt,
                ContinuousClock.now - authenticatedAt < .seconds(Self.reuseSeconds)
            {
                return context
            }
            if authenticating {
                // Another approval's prompt is up: share its answer (a cancel cancels the whole burst).
                try await withCheckedThrowingContinuation { waiters.append($0) }
                continue
            }
            forget()
            authenticating = true
            let fresh = Self.makeContext(reason: reason)
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    fresh.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
                        success, error in
                        if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: Self.mapped(error ?? RemoteKeyError.notAuthenticated))
                        }
                    }
                }
            } catch {
                authenticating = false
                finishWaiters(with: error)
                throw error
            }
            context = fresh
            authenticatedAt = .now
            authenticating = false
            finishWaiters(with: nil)
            return fresh
        }
    }

    /// A context for one Face ID check. Biometry only (no passcode button), and no reuse of the phone's own unlock:
    /// `touchIDAuthenticationAllowableReuseDuration` stays 0, because a positive value lets a Face ID unlock of the
    /// iPhone itself in that window answer this check without a prompt, so whoever picked up a just-unlocked phone could
    /// approve or unlock acting on the Mac (security review 2026-10-30, S-01). The 30 s that one check covers (3.6) is
    /// this gate's own reuse of a context the person evaluated for Pebble Remote, counted from that check.
    static func makeContext(reason: String) -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        context.localizedReason = reason
        context.localizedFallbackTitle = ""
        return context
    }

    private func finishWaiters(with error: (any Error)?) {
        let waiting = waiters
        waiters = []
        for waiter in waiting {
            if let error { waiter.resume(throwing: error) } else { waiter.resume() }
        }
    }

    /// The evaluated context is dropped, so no approval reuses it. A prompt that is up is left alone: its answer makes a
    /// context of its own.
    func endWindow() {
        forget()
    }

    private func forget() {
        context?.invalidate()
        context = nil
        authenticatedAt = nil
    }

    /// A cancelled prompt becomes `RemoteCallError.cancelledByPerson`; everything else a content-free key error.
    static func mapped(_ error: any Error) -> any Error {
        if error is RemoteCallError || error is RemoteKeyError { return error }
        let nsError = error as NSError
        guard nsError.domain == LAErrorDomain else { return RemoteKeyError.signingFailed }
        switch LAError.Code(rawValue: nsError.code) {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            return RemoteCallError.cancelledByPerson
        case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout, .passcodeNotSet:
            return RemoteKeyError.biometryUnavailable
        case .authenticationFailed:
            return RemoteKeyError.notAuthenticated
        default:
            return RemoteKeyError.signingFailed
        }
    }
}

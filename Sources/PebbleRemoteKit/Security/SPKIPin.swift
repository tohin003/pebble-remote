import CryptoKit
import Foundation
import Security

/// The bridge's certificate pin (contract section 3.1): base64url, no padding, of SHA-256 over the DER
/// SubjectPublicKeyInfo of its ECDSA P-256 key. Only the key is pinned, so the Mac may re-issue its certificate with
/// the same key; no other key is accepted, whoever signed its certificate.
public enum SPKIPin {
    /// A P-256 SubjectPublicKeyInfo's DER up to its 65-byte point: SEQUENCE { SEQUENCE { id-ecPublicKey,
    /// prime256v1 }, BIT STRING (no unused bits) }.
    public static let p256Prefix: [UInt8] = [
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48,
        0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ]

    /// The SHA-256 digest of the SubjectPublicKeyInfo, or nil unless `x963` is an uncompressed P-256 point on the
    /// curve (65 bytes, starting 0x04).
    public static func digest(x963 publicKey: Data) -> Data? {
        guard publicKey.count == 65, publicKey.first == 0x04,
            (try? P256.Signing.PublicKey(x963Representation: publicKey)) != nil
        else { return nil }
        var hash = SHA256()
        hash.update(data: p256Prefix)
        hash.update(data: publicKey)
        return Data(hash.finalize())
    }

    /// The pin for an X9.63 uncompressed P-256 public key, or nil if it is not one.
    public static func pin(x963 publicKey: Data) -> String? {
        digest(x963: publicKey).map(Base64URL.encode)
    }

    public static func pin(for key: P256.Signing.PublicKey) -> String {
        Base64URL.encode(Data(SHA256.hash(data: key.derRepresentation)))
    }

    /// The X9.63 point of a public `SecKey`, or nil unless it is an elliptic-curve P-256 key.
    public static func p256Point(of key: SecKey) -> Data? {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
            let type = attributes[kSecAttrKeyType] as? String, type == (kSecAttrKeyTypeECSECPrimeRandom as String),
            (attributes[kSecAttrKeySizeInBits] as? NSNumber)?.intValue == 256
        else { return nil }
        var error: Unmanaged<CFError>?
        guard let external = SecKeyCopyExternalRepresentation(key, &error) as Data?, external.count == 65,
            external.first == 0x04
        else {
            error?.release()
            return nil
        }
        return external
    }

    /// The SHA-256 SPKI digest of the leaf certificate's key in `trust`; nil when there is no leaf or its key is not
    /// P-256 (an RSA or P-384 key is refused, never pinned).
    public static func leafDigest(of trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
            let key = SecCertificateCopyKey(leaf), let point = p256Point(of: key)
        else { return nil }
        return digest(x963: point)
    }

    public static func leafPin(of trust: SecTrust) -> String? {
        leafDigest(of: trust).map(Base64URL.encode)
    }

    /// Compares a computed SPKI digest with the expected pin in constant time. A pin that is not 32 bytes of
    /// base64url never matches.
    public static func matches(digest: Data?, pin expected: String) -> Bool {
        guard let digest, let wanted = Base64URL.decode(expected), wanted.count == 32 else { return false }
        return ConstantTime.equal(digest, wanted)
    }

    /// The TLS check: the leaf's key must be P-256 and hash to `pin`.
    public static func trust(_ trust: SecTrust, matches pin: String) -> Bool {
        matches(digest: leafDigest(of: trust), pin: pin)
    }
}

import CryptoKit
import Foundation
import PebbleProtocol
import Security
import Testing

@testable import PebbleRemoteKit

// Lane B: base64url, transcripts, pins, keys and the Keychain-shaped stores. Fixed vectors were made independently
// with OpenSSL (LibreSSL 3.3.6) from the private scalar 0x01...0x20.
enum Vectors {
    static let privateScalar = Data(1...32)
    static let publicX963Hex =
        "04515c3d6eb9e396b904d3feca7f54fdcd0cc1e997bf375dca515ad0a6c3b4035f4536be3a50f318fbf9a5475902a221502bef0d57e08c53b2cc0a56f17d9f9354"
    static let publicX963Text = "BFFcPW6545a5BNP-yn9U_c0MwemXvzddylFa0KbDtANfRTa-OlDzGPv5pUdZAqIhUCvvDVfgjFOyzApW8X2fk1Q"
    /// `openssl dgst -sha256 -binary` of the SubjectPublicKeyInfo, base64url.
    static let pin = "8dWUSbcnFl3nMr8oMzgSK5liimFZGP7cZ9h4__z0fac"
    /// `openssl dgst -sha256 -sign` over T_hello("bridge-1", "dev-1", "bm9uY2U", "PIN").
    static let opensslHelloSignature =
        "MEYCIQD9HvzdUVsaKlMjzSA_GrLlNZ39WF90TVL6OJcNOm8vhQIhAMgSvZtilu1CpMkv-EN1dgu4I3Ejeo9tLJqSCWn0Y4Os"
    /// Self-signed certificates: the key above (P-256), a P-384 key, an RSA-2048 key.
    static let p256Certificate =
        "MIIBGjCBwgIJAL04vZI6gOokMAoGCCqGSM49BAMCMBYxFDASBgNVBAMMC3BlYmJsZS10ZXN0MB4XDTI2MTAyOTE4MDYzNloXDTM2MTAyNjE4MDYzNlowFjEUMBIGA1UEAwwLcGViYmxlLXRlc3QwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAARRXD1uueOWuQTT/sp/VP3NDMHpl783XcpRWtCmw7QDX0U2vjpQ8xj7+aVHWQKiIVAr7w1X4IxTsswKVvF9n5NUMAoGCCqGSM49BAMCA0cAMEQCIALbDRdilkfyKjj+F8FVjrVnL6hyUW+tHmmS5uMrzKsyAiB69noVSfvgDUpVN9MaI1vvGPfKksrGAg9KWHNFf2twmA=="
    static let p384Certificate =
        "MIIBXzCB5wIJAL7wvNmC7gCkMAoGCCqGSM49BAMCMBoxGDAWBgNVBAMMD3BlYmJsZS10ZXN0LTM4NDAeFw0yNjEwMjkxODA2MzZaFw0zNjEwMjYxODA2MzZaMBoxGDAWBgNVBAMMD3BlYmJsZS10ZXN0LTM4NDB2MBAGByqGSM49AgEGBSuBBAAiA2IABOl+FG5XAaoSpGYfYQRNGNvyk4H0nyc14WYwT9UNwqBWzxI4t8wrvIhR1s894j5DA6KPqI9hVzTImiCWQX25XeMch1Mi/RWci+nmq5vJXK2ib8y8L48svLJYplb2Pbe1VjAKBggqhkjOPQQDAgNnADBkAi9aGwRypyXypozski1NCs+KmFjt/BaKxdQNmlyRM2flgps2WcqHO+CNhz79zqBjnQIxAIcah+iCdEfqcZvG0Fh5MyjbUKJM0l8VMDSl+0WUmzAwrHIA7cS30iteWlhg2yLryw=="
    static let rsaCertificate =
        "MIICsDCCAZgCCQCGPJTMBXPELTANBgkqhkiG9w0BAQsFADAaMRgwFgYDVQQDDA9wZWJibGUtdGVzdC1yc2EwHhcNMjYxMDI5MTgwNjM2WhcNMzYxMDI2MTgwNjM2WjAaMRgwFgYDVQQDDA9wZWJibGUtdGVzdC1yc2EwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDMzyWVnFYcLNDNSRiyKx9xVua+6CkEU0CPqvUO+eoByR/vmxbI4vyzSBkRer86b/DauoDW4s2y05GmpvNzrgOFdbzjvtkV6ERJEPLNCRxVUtmLS5i0306Dg5rsbM0l5WhRQZ8SEIgyPqbrlJTUm1pnrYhXcR47IoaKheqcrwabGLMORUgtMEbY1+HYrMVw83Ep+DPEApNv1D9P/wD9LJECYMMUsO/8oBwfRGyUetNoBWI+hJ2D0HajVdWKQvUhxqaqQY3RvTCWjkJ3SKrLzG0dzRtOLN3vOfoHNiQKzIGSFk0W98YJi6ELQVT+94VJql2PAtMyisdu1EJYpHrxbCHJAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAAVimQtwRQywVCGFld+I1C0bXhr8pWJpv4ws6GClvKLM4ekOCi1bLYwYEs7X/FTsjiZ9pT8Mwy5+WF0nibTgl9dGWT9eJTIvNIdcis0/YD8/1ADcz5XqlFZbwmIcrXI3gVLNC+cN7qvcR2bsBEpt2Ut6Dm6Bc6vNXeqo3SnGuTAcnAsYB22vK9Ihe9vzrzY8oeFDmYd8IsOTCzF4P1CWC0fm7ct1XrRm61K+qWmiv5GJUvCgQGiDOlpNAT2yECvHNXot1GfN1z9dsQREe7QjJeGTRkq4NqiaU9P0DZJ9Tdz1FAZLcYh/p7yARjzKfRC/VVLUxratg0eKRmLO95eYl+I="

    static func privateKey() throws -> P256.Signing.PrivateKey {
        try P256.Signing.PrivateKey(rawRepresentation: privateScalar)
    }

    static func trust(fromBase64 text: String) throws -> SecTrust {
        let der = try #require(Data(base64Encoded: text))
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)
        #expect(status == errSecSuccess)
        return try #require(trust)
    }
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

@Suite("Lane B: base64url")
struct Base64URLTests {
    @Test func encodesRFC4648VectorsWithoutPadding() {
        let vectors = ["": "", "f": "Zg", "fo": "Zm8", "foo": "Zm9v", "foob": "Zm9vYg", "fooba": "Zm9vYmE", "foobar": "Zm9vYmFy"]
        for (plain, encoded) in vectors {
            #expect(Base64URL.encode(Data(plain.utf8)) == encoded)
            #expect(Base64URL.decode(encoded) == Data(plain.utf8))
        }
        #expect(Base64URL.encode(Data([0xfb, 0xff, 0xbf])) == "-_-_")
        #expect(Data([0xfb, 0xff]).base64URLEncoded == "-_8")
        #expect(Data(base64URLEncoded: "-_8") == Data([0xfb, 0xff]))
    }

    @Test func decodingIsStrict() {
        for bad in ["Zm9v=", "Zm9vYg==", "+/8", "Zm9v Yg", "Z", "Zm9vY", " Zm9v", "Zm9v\n", "é"] {
            #expect(Base64URL.decode(bad) == nil, "\(bad) should be refused")
        }
    }

    @Test func roundTripsRandomBytes() {
        var generator = SystemRandomNumberGenerator()
        for length in 0..<70 {
            let bytes = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
            #expect(Base64URL.decode(Base64URL.encode(bytes)) == bytes)
        }
    }

    @Test func constantTimeEquality() {
        #expect(ConstantTime.equal(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!ConstantTime.equal(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!ConstantTime.equal(Data([1, 2, 3]), Data([1, 2])))
        #expect(ConstantTime.equal(Data(), Data()))
    }
}

@Suite("Lane B: signed transcripts")
struct TranscriptTests {
    @Test func helloIsExactBytes() throws {
        let bytes = try SignedTranscript.hello(bridgeID: "bridge-1", deviceID: "dev-1", nonce: "bm9uY2U", pin: "PIN")
        #expect(String(decoding: bytes, as: UTF8.self) == "pebble-remote/v1/hello\nbridge-1\ndev-1\nbm9uY2U\nPIN\n")
    }

    @Test func pairIsExactBytes() throws {
        let bytes = try SignedTranscript.pair(
            bridgeID: "b", nonce: "n", pin: "p", code: "c", deviceKey: "dk", approveKey: "ak")
        #expect(String(decoding: bytes, as: UTF8.self) == "pebble-remote/v1/pair\nb\nn\np\nc\ndk\nak\n")
    }

    @Test func proofIsExactBytesWithParamsDigest() throws {
        let params = try FrameCodec.jsonText(["id": "c1", "action_id": "a9"])
        #expect(params == #"{"action_id":"a9","id":"c1"}"#)
        // python3: base64url(sha256(b'{"action_id":"a9","id":"c1"}'))
        #expect(SignedTranscript.paramsDigest(params) == "IjGkhgxEHL96SaH_YpvZ_QIRTIdaiepSsS2nStVZGXM")
        // v0.3 (3.11 item 3): the connection's nonce and the call's idem are signed too. The vector posted for lane C.
        let bytes = try SignedTranscript.proof(
            bridgeID: "bridge-1", deviceID: "dev-1", epoch: "e7", nonce: "bm9uY2U", requestID: "r42",
            idem: "0b5e7a2c-9d1f-4e8a-b3c6-2f4d5e6a7b8c", method: "approve", paramsJSON: params,
            timestamp: 1_761_772_800_123)
        #expect(
            String(decoding: bytes, as: UTF8.self)
                == "pebble-remote/v1/proof\nbridge-1\ndev-1\ne7\nbm9uY2U\nr42\n0b5e7a2c-9d1f-4e8a-b3c6-2f4d5e6a7b8c\napprove\nIjGkhgxEHL96SaH_YpvZ_QIRTIdaiepSsS2nStVZGXM\n1761772800123\n")
        #expect(
            Data(SHA256.hash(data: bytes)).map { String(format: "%02x", $0) }.joined()
                == "f6b0a2691eaa69136cfe30928ea597c3cbbca499378d8a35360a0b6f22c98c57")
    }

    @Test func proofMatchesLaneCsGoldenVector() throws {
        // Lane C's golden vector (board, 01:16), checked by the mock's own T_proof.
        let bytes = try SignedTranscript.proof(
            bridgeID: "b-1", deviceID: "d-1", epoch: "e-1", nonce: "n-1", requestID: "r42",
            idem: "0f8fad5b-d9cb-469f-a165-70867728950e", method: "approve", paramsJSON: #"{"action_id":"a9","id":"c1"}"#,
            timestamp: 1_761_780_000_000)
        #expect(
            Data(SHA256.hash(data: bytes)).map { String(format: "%02x", $0) }.joined()
                == "d0e32872b7515632da3ffaa1059db00ad0ba78c80297ed5c495492479d70a19e")
    }

    @Test func refusesLineBreaksInFields() {
        #expect(throws: SignedTranscript.LineBreakInField.self) {
            try SignedTranscript.hello(bridgeID: "b", deviceID: "d", nonce: "n\nx", pin: "p")
        }
        #expect(throws: SignedTranscript.LineBreakInField.self) {
            try SignedTranscript.hello(bridgeID: "b\r\n", deviceID: "d", nonce: "n", pin: "p")
        }
    }

    @Test func fixedKeyMatchesOpenSSL() throws {
        let key = try Vectors.privateKey()
        #expect(key.publicKey.x963Representation == Data(hex: Vectors.publicX963Hex))
        #expect(SoftwareSigningKey(role: .device, privateKey: key).publicKeyText == Vectors.publicX963Text)
    }

    @Test func opensslSignatureOverHelloVerifies() throws {
        let key = try Vectors.privateKey()
        let transcript = try SignedTranscript.hello(
            bridgeID: "bridge-1", deviceID: "dev-1", nonce: "bm9uY2U", pin: "PIN")
        let der = try #require(Data(base64URLEncoded: Vectors.opensslHelloSignature))
        let signature = try P256.Signing.ECDSASignature(derRepresentation: der)
        #expect(key.publicKey.isValidSignature(signature, for: transcript))
        #expect(!key.publicKey.isValidSignature(signature, for: transcript + Data("x".utf8)))
    }

    @Test func softwareKeySignsDERThatVerifies() async throws {
        let signer = SoftwareSigningKey(role: .approve, privateKey: try Vectors.privateKey())
        let transcript = try SignedTranscript.proof(
            bridgeID: "b", deviceID: "d", epoch: "e", nonce: "n", requestID: "r1", idem: "i", method: "approve",
            paramsJSON: "{}", timestamp: 1)
        let der = try await signer.sign(transcript, reason: "Approve")
        #expect(der.first == 0x30)  // DER SEQUENCE
        let signature = try P256.Signing.ECDSASignature(derRepresentation: der)
        #expect(signer.publicKey.isValidSignature(signature, for: transcript))
    }
}

@Suite("Lane B: SPKI pins")
struct PinTests {
    @Test func pinOfFixedKeyMatchesOpenSSL() throws {
        let key = try Vectors.privateKey()
        #expect(SPKIPin.pin(x963: key.publicKey.x963Representation) == Vectors.pin)
        #expect(SPKIPin.pin(for: key.publicKey) == Vectors.pin)
        // The fixed prefix plus the point is exactly CryptoKit's DER SubjectPublicKeyInfo.
        #expect(Data(SPKIPin.p256Prefix) + key.publicKey.x963Representation == key.publicKey.derRepresentation)
    }

    @Test func refusesWhatIsNotAP256Point() {
        #expect(SPKIPin.pin(x963: Data(repeating: 4, count: 65)) == nil)  // not on the curve
        #expect(SPKIPin.pin(x963: Data(hex: Vectors.publicX963Hex).dropLast()) == nil)
        #expect(SPKIPin.pin(x963: Data()) == nil)
    }

    @Test func pinFromCertificateLeaf() throws {
        let trust = try Vectors.trust(fromBase64: Vectors.p256Certificate)
        #expect(SPKIPin.leafPin(of: trust) == Vectors.pin)
        #expect(SPKIPin.trust(trust, matches: Vectors.pin))
        #expect(!SPKIPin.trust(trust, matches: "AAAA" + Vectors.pin.dropFirst(4)))
        #expect(!SPKIPin.trust(trust, matches: "not a pin"))
    }

    @Test func refusesOtherKeyTypes() throws {
        let p384 = try Vectors.trust(fromBase64: Vectors.p384Certificate)
        let rsa = try Vectors.trust(fromBase64: Vectors.rsaCertificate)
        #expect(SPKIPin.leafPin(of: p384) == nil)
        #expect(SPKIPin.leafPin(of: rsa) == nil)
        #expect(!SPKIPin.trust(rsa, matches: Vectors.pin))
    }

    @Test func matchingIsByBytes() throws {
        let digest = try #require(Data(base64URLEncoded: Vectors.pin))
        #expect(SPKIPin.matches(digest: digest, pin: Vectors.pin))
        #expect(!SPKIPin.matches(digest: digest, pin: Vectors.pin + "A"))
        #expect(!SPKIPin.matches(digest: nil, pin: Vectors.pin))
        #expect(!SPKIPin.matches(digest: digest.dropLast(), pin: Base64URL.encode(digest.dropLast())))
    }
}

@Suite("Lane B: keys and stores")
struct KeyStoreTests {
    @Test func softwareKeysAreKeptOnlyWhenSaved() async throws {
        let store = InMemorySecretStore()
        let provider = SoftwareKeyProvider(store: store)
        let keys = try await provider.makeKeys()
        #expect(try await provider.keys(for: "b1") == nil)
        #expect(store.accounts.isEmpty)
        try await provider.save(keys, for: "b1")
        let loaded = try #require(try await provider.keys(for: "b1"))
        #expect(loaded.device.publicKeyX963 == keys.device.publicKeyX963)
        #expect(loaded.approve.publicKeyX963 == keys.approve.publicKeyX963)
        #expect(loaded.device.role == .device && loaded.approve.role == .approve)
        #expect(keys.device.publicKeyX963 != keys.approve.publicKeyX963)
        try await provider.deleteKeys(for: "b1")
        #expect(try await provider.keys(for: "b1") == nil)
    }

    @Test func foreignKeysAreRefused() async throws {
        let enclave = SecureEnclaveKeyProvider(store: InMemorySecretStore())
        let software = try await SoftwareKeyProvider().makeKeys()
        await #expect(throws: RemoteKeyError.foreignKey) { try await enclave.save(software, for: "b") }
    }

    @Test func storedSecureEnclaveRecordReadsBackWithoutTheEnclave() async throws {
        // A stored record carries the public keys, so reading it back never needs the Secure Enclave or Face ID.
        let device = try Vectors.privateKey().publicKey
        let approve = P256.Signing.PrivateKey().publicKey
        let record = StoredKeyPair(
            kind: .secureEnclave, device: Data([1]), approve: Data([2]), devicePublic: device.x963Representation,
            approvePublic: approve.x963Representation)
        let store = InMemorySecretStore([StoredKeyPair.account(for: "b"): try record.encoded()])
        let keys = try #require(try await SecureEnclaveKeyProvider(store: store).keys(for: "b"))
        #expect(keys.device.publicKeyText == Vectors.publicX963Text)
        #expect(keys.approve.publicKeyX963 == approve.x963Representation)
        await #expect(throws: RemoteKeyError.unreadableStoredKeys) {
            try await SoftwareKeyProvider(store: store).keys(for: "b")
        }
    }

    @Test func pairedMacRoundTripsThroughTheStore() throws {
        let store = KeychainPairedMacStore(store: InMemorySecretStore())
        #expect(try store.load() == nil)
        let mac = PairedMac(
            bridgeID: "b1", name: "Studio Mac", deviceID: "d1", pin: Vectors.pin,
            endpoints: [Endpoint(host: "192.168.1.20", port: 47800), Endpoint(host: "fe80::1", port: 47800)],
            pairedAt: Date(timeIntervalSince1970: 1_761_772_800))
        try store.save(mac)
        #expect(try store.load() == mac)
        try store.remove()
        #expect(try store.load() == nil)
        try store.remove()  // not an error when nothing is kept
    }

    @Test func cancelledFaceIDBecomesCancelledByPerson() {
        for code in [LAErrorCodeForTests.userCancel, .appCancel, .systemCancel, .userFallback] {
            let error = NSError(domain: "com.apple.LocalAuthentication", code: code.rawValue)
            #expect(ApprovalGate.mapped(error) as? RemoteCallError == .cancelledByPerson)
        }
        let lockout = NSError(domain: "com.apple.LocalAuthentication", code: LAErrorCodeForTests.biometryLockout.rawValue)
        #expect(ApprovalGate.mapped(lockout) as? RemoteKeyError == .biometryUnavailable)
        #expect(ApprovalGate.mapped(CocoaError(.fileNoSuchFile)) as? RemoteKeyError == .signingFailed)
    }
}

/// LocalAuthentication's error codes (LAError.h), so the mapping test needs no Face ID.
enum LAErrorCodeForTests: Int {
    case userCancel = -2
    case userFallback = -3
    case systemCancel = -4
    case appCancel = -9
    case biometryLockout = -8
}

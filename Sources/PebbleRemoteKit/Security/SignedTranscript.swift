import CryptoKit
import Foundation

/// The exact bytes each signature covers (contract sections 3.2, 3.3 and 3.6, with 3.11 item 3): fixed lines, each followed by "\n",
/// in UTF-8. Keys, nonces, codes and pins appear as the base64url text sent on the wire, never re-encoded; `ts` is
/// decimal unix milliseconds. Signatures over them are DER ECDSA P-256 with SHA-256 (CryptoKit's `P256.Signing`).
public enum SignedTranscript {
    public static let pairLabel = "pebble-remote/v1/pair"
    public static let helloLabel = "pebble-remote/v1/hello"
    public static let proofLabel = "pebble-remote/v1/proof"
    /// X-1's check code is hashed from this line (followed by "\n") and T_pair; nothing signs it (see `PairingCode`).
    public static let sasLabel = "pebble-remote/v1/sas"

    /// A field held a line break, which would let two different field lists sign the same bytes. Content-free: it
    /// names the field, never its value.
    public struct LineBreakInField: Error, Sendable, Hashable, CustomStringConvertible {
        public var field: String
        public var description: String { "line break in transcript field \(field)" }
    }

    /// T_pair: `pebble-remote/v1/pair`, bid, nonce, pin, code, device_key, approve_key.
    public static func pair(
        bridgeID: String, nonce: String, pin: String, code: String, deviceKey: String, approveKey: String
    ) throws -> Data {
        try lines(
            pairLabel,
            [
                ("bid", bridgeID), ("nonce", nonce), ("pin", pin), ("code", code), ("device_key", deviceKey),
                ("approve_key", approveKey),
            ])
    }

    /// T_hello: `pebble-remote/v1/hello`, bid, device_id, nonce, pin. The pin is the one checked in TLS, which binds
    /// the signature to this TLS channel.
    public static func hello(bridgeID: String, deviceID: String, nonce: String, pin: String) throws -> Data {
        try lines(helloLabel, [("bid", bridgeID), ("device_id", deviceID), ("nonce", nonce), ("pin", pin)])
    }

    /// T_proof (contract v0.3): `pebble-remote/v1/proof`, bid, device_id, epoch, nonce, id, idem, method,
    /// b64url(SHA-256(params_json)), ts. The nonce is this connection's `challenge.nonce` and `idem` the call's key,
    /// so a proof is bound to one connection and one call and cannot be replayed on another.
    public static func proof(
        bridgeID: String, deviceID: String, epoch: String, nonce: String, requestID: String, idem: String,
        method: String, paramsJSON: String, timestamp: Int64
    ) throws -> Data {
        try lines(
            proofLabel,
            [
                ("bid", bridgeID), ("device_id", deviceID), ("epoch", epoch), ("nonce", nonce), ("id", requestID),
                ("idem", idem), ("method", method), ("params_sha256", paramsDigest(paramsJSON)),
                ("ts", String(timestamp)),
            ])
    }

    /// base64url(SHA-256(the params text as UTF-8)).
    public static func paramsDigest(_ paramsJSON: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(paramsJSON.utf8))))
    }

    private static func lines(_ label: String, _ fields: [(name: String, value: String)]) throws -> Data {
        var text = label + "\n"
        for (name, value) in fields {
            guard !value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
                throw LineBreakInField(field: name)
            }
            text += value + "\n"
        }
        return Data(text.utf8)
    }
}

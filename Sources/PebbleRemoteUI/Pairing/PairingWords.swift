import PebbleDesign
import PebbleRemoteKit

/// Pairing failures in words that say what to do, for the content-free codes the client reports while pairing
/// (lane B's `RemoteCallError.transport` codes, worded by PebbleDesign). Anything else keeps the store's own notice
/// (Pebble's or the bridge's words, such as a used or expired pairing link).
enum PairingWords {
    static func message(for error: any Error) -> String? {
        guard case .transport(let code)? = error as? RemoteCallError else { return nil }
        return AppCopy.Errors.forCode(code)
    }
}

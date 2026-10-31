import Foundation
import PebbleProtocol

extension BridgeInfo {
    /// Whether the bridge wants a Face ID proof for this call, from `welcome.elevated` (contract 3.6, the source of
    /// truth). Entries may name a setting key, `setting:<key>` (v0.3 item 5), so a `setting` call needs a proof only
    /// for the keys listed; an older bridge that lists plain `setting` means the `permissions` key.
    public func needsProof(_ method: String, _ params: JSONValue = .object([:])) -> Bool {
        guard method == "setting" else { return elevated.contains(method) }
        guard let key = params["key"]?.string else { return false }
        return elevated.contains("setting:\(key)") || (key == "permissions" && elevated.contains("setting"))
    }

    /// Whether this bridge asks for the unlock before calls that act (contract C1).
    public var offersUnlock: Bool { methods.contains("remote.unlock") || elevated.contains("remote.unlock") }
}

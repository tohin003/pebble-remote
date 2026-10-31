import Foundation

/// One event from the bridge: a Pebble event relayed as Pebble emitted it (`token`, `progress`, `run`, `actions`, ...),
/// or one of the bridge's own (`remote.*`). `seq` grows by one per event within an `epoch`; the phone resumes from it.
/// Contract: the bridge contract, section 5.
public struct PebbleEvent: Sendable, Hashable {
    public var seq: Int
    public var name: String
    public var data: JSONValue
    /// The Mac's clock when the bridge sent it, if the bridge said.
    public var time: Date?

    public init(seq: Int, name: String, data: JSONValue, time: Date? = nil) {
        self.seq = seq
        self.name = name
        self.data = data
        self.time = time
    }

    /// The conversation the event belongs to, when it names one.
    public var chatID: String? { data["chat_id"]?.string }
}

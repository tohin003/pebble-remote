import Foundation
import PebbleProtocol

/// The store's only way to reach Pebble. The live implementation (lane B: Transport + Security) speaks the bridge
/// contract; DemoClient (lane A) simulates Pebble inside the app; tests use fakes.
public protocol RemoteClient: AnyObject, Sendable {
    /// Status changes and events, in the order they happened. One consumer: the store.
    var updates: AsyncStream<ClientUpdate> { get }

    /// Starts connecting (racing the Mac's endpoints) and keeps the connection up until `disconnect()`.
    func connect(to mac: PairedMac) async
    /// Closes politely; used when the app goes to the background.
    func disconnect() async

    /// One of Pebble's methods (or the bridge's `remote.*`), relayed by the bridge. Throws RemoteCallError.
    func call(_ method: String, _ params: JSONValue) async throws -> JSONValue
    /// A call the bridge accepts only with the person's Face ID: the client signs it with the approval key, which
    /// asks for Face ID. `reason` is the sentence Face ID shows ("Approve: run npm test").
    func callElevated(_ method: String, _ params: JSONValue, reason: String) async throws -> JSONValue

    /// Pairs with a Mac from the link it showed (QR or pasted). Returns what to keep in the Keychain.
    func pair(_ link: PairingLink, deviceName: String) async throws -> PairedMac
    /// The same, telling `showingCode` the six digits to compare with the Mac's once the phone has sent its signatures
    /// (contract X-1): the Mac sends `paired` only after the person confirms there that the codes match, which can take
    /// up to two minutes, and the person cancelling (the calling task is cancelled) ends the wait. Clients that have no
    /// such step use the default, which pairs without showing a code.
    func pair(
        _ link: PairingLink, deviceName: String, showingCode: @escaping @Sendable (PairingCode) -> Void
    ) async throws -> PairedMac

    /// Deletes what the client keeps for this Mac (its pairing keys, its resume point). Called when the person forgets
    /// the Mac or pairs another one. Clients that keep nothing use the default, which does nothing.
    func forget(_ mac: PairedMac) async

    /// Asks for Face ID and unlocks acting on the Mac for the bridge's `unlock_seconds` (contract C1). The client
    /// reports the time it lasts until with `ClientUpdate.unlocked(until:)`, after this and after every elevated call
    /// (each counts as an unlock). The default sends the elevated `remote.unlock`.
    func unlock(reason: String) async throws

    /// Ends this phone's unlock at once (contract S-05): the client reports it with `ClientUpdate.unlocked(until: nil)`
    /// and, when the bridge offers `remote.lock`, asks it to end the device's unlock too, briefly and ignoring failure.
    /// Called when the app goes to the background and when the app lock engages. A bridge without `remote.lock` is not
    /// asked. Clients that hold no unlock use the default, which does nothing.
    func lock() async
}

extension RemoteClient {
    public func forget(_ mac: PairedMac) async {}

    public func pair(
        _ link: PairingLink, deviceName: String, showingCode: @escaping @Sendable (PairingCode) -> Void
    ) async throws -> PairedMac {
        try await pair(link, deviceName: deviceName)
    }

    public func lock() async {}

    public func unlock(reason: String) async throws {
        _ = try await callElevated("remote.unlock", .object([:]), reason: reason)
    }
}

public enum ClientUpdate: Sendable {
    case status(ConnectionStatus)
    /// What the bridge said about itself and Pebble when the connection was accepted.
    case welcome(BridgeInfo)
    case event(PebbleEvent)
    /// The bridge could not replay the events missed while away: refetch state and every open chat.
    case resyncNeeded
    /// Acting on the Mac is unlocked until then (contract C1), or locked (nil): after an unlock, after any elevated
    /// call, and when the time passes or the connection is replaced.
    case unlocked(until: Date?)
}

public struct BridgeInfo: Sendable, Hashable {
    public var bridgeVersion: String
    public var macName: String
    public var pebbleRunning: Bool
    public var pebbleVersion: String?
    /// Methods this bridge accepts from the phone; the app hides what is missing (feature detection).
    public var methods: Set<String>
    /// Methods that need a Face ID proof (and settings keys, as `setting:<key>`).
    public var elevated: Set<String>
    public var resumed: Bool
    /// How long an unlock lets this phone act (contract C1, `welcome.unlock_seconds`); nil from an older bridge.
    public var unlockSeconds: Int?

    public init(
        bridgeVersion: String, macName: String, pebbleRunning: Bool, pebbleVersion: String?, methods: Set<String>,
        elevated: Set<String>, resumed: Bool, unlockSeconds: Int? = nil
    ) {
        self.bridgeVersion = bridgeVersion
        self.macName = macName
        self.pebbleRunning = pebbleRunning
        self.pebbleVersion = pebbleVersion
        self.methods = methods
        self.elevated = elevated
        self.resumed = resumed
        self.unlockSeconds = unlockSeconds
    }
}

public enum RemoteCallError: Error, Sendable, Hashable {
    /// Pebble or the bridge refused, in words meant for the person.
    case refused(PersonFacingError)
    case notConnected
    case timedOut
    /// The person cancelled Face ID.
    case cancelledByPerson
    case transport(String)
    case notImplemented(String)
}

import Foundation
import Network
import PebbleProtocol
import Security
import Synchronization

/// Opens the bridge's WebSocket with Network.framework (contract 3.1): `wss://<host>:<port>/pebble-remote/v1`,
/// subprotocol `pebble-remote.v1`, TLS 1.3 only, the server's key checked against the pin in TLS's verify block (no
/// certificate authority is consulted, and no other key is accepted), TCP_NODELAY, pings answered automatically.
public struct NetworkSocketConnector: FrameSocketConnector {
    /// How long TCP, TLS and the WebSocket upgrade together may take.
    public var openTimeout: Duration
    /// The largest message accepted from the bridge.
    public var maximumMessageSize: Int

    public init(openTimeout: Duration = .seconds(10), maximumMessageSize: Int = 16 << 20) {
        self.openTimeout = openTimeout
        self.maximumMessageSize = maximumMessageSize
    }

    public func open(_ endpoint: Endpoint, pin: String) async throws -> any FrameSocket {
        guard let url = Self.url(for: endpoint) else { throw FrameSocketError.unreachable("bad address") }
        let socket = NetworkFrameSocket(url: url, pin: pin, maximumMessageSize: maximumMessageSize)
        try await socket.open(timeout: openTimeout)
        return socket
    }

    /// `wss://host:port/pebble-remote/v1`; an IPv6 literal goes in brackets, its zone's "%" encoded. Nil for a host that
    /// is not a plain name or address (an endpoint kept from an older version, or one Bonjour resolved): "@", "/" or "?"
    /// in it would point the URL at another host or port (security review 2026-10-30, S-06).
    static func url(for endpoint: Endpoint) -> URL? {
        guard Endpoint.isValidHost(endpoint.host) else { return nil }
        var host = endpoint.host
        if host.contains(":") {
            host = "[" + host.replacingOccurrences(of: "%", with: "%25") + "]"
        }
        return URL(string: "wss://\(host):\(endpoint.port)\(RemoteContract.path)")
    }
}

/// One NWConnection carrying the WebSocket.
final class NetworkFrameSocket: FrameSocket {
    private enum Incoming: Sendable {
        case text(String)
        case control
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let pinCheck: PinCheck
    private let ready = OneShot<Void>()
    private let closing = Mutex(false)

    init(url: URL, pin: String, maximumMessageSize: Int) {
        let queue = DispatchQueue(label: "PebbleRemote.socket", qos: .userInitiated)
        let pinCheck = PinCheck()

        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(security, .TLSv13)
        // No session resumption: a resumed TLS 1.3 handshake sends no certificate, so the verify block below would have
        // nothing to check. Every connection presents the bridge's certificate and is checked against the pin of the
        // Mac it is for, whatever an earlier connection to the same address was (security review 2026-10-30, S-12).
        sec_protocol_options_set_tls_resumption_enabled(security, false)
        sec_protocol_options_set_tls_tickets_enabled(security, false)
        sec_protocol_options_set_verify_block(
            security,
            { _, trust, complete in
                let accepted = SPKIPin.trust(sec_trust_copy_ref(trust).takeRetainedValue(), matches: pin)
                if !accepted { pinCheck.markMismatch() }
                complete(accepted)
            }, queue)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true

        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        webSocket.maximumMessageSize = maximumMessageSize
        webSocket.setSubprotocols([RemoteContract.subprotocol])

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)

        self.queue = queue
        self.pinCheck = pinCheck
        self.connection = NWConnection(to: .url(url), using: parameters)
    }

    deinit {
        connection.cancel()
    }

    func open(timeout: Duration) async throws {
        let ready = self.ready
        let pinCheck = self.pinCheck
        let connection = self.connection
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.succeed(())
            case .waiting(let error), .failed(let error):
                // `.waiting` (refused, no route) would retry forever; the race moves on to other endpoints instead.
                // A Local Network switch that is off shows only in the path (Apple TN3179).
                let denied = connection.currentPath?.unsatisfiedReason == .localNetworkDenied
                ready.fail(
                    pinCheck.mismatched
                        ? FrameSocketError.pinMismatch : denied ? FrameSocketError.localNetworkDenied : Self.openFailure(error))
                connection.cancel()
            case .cancelled:
                ready.fail(pinCheck.mismatched ? FrameSocketError.pinMismatch : FrameSocketError.closed)
            default:
                break
            }
        }
        connection.start(queue: queue)
        let timer = Task {
            try await Task.sleep(for: timeout)
            ready.fail(FrameSocketError.unreachable("timed out"))
            connection.cancel()
        }
        defer { timer.cancel() }
        do {
            try await ready.value(onCancel: { connection.cancel() })
        } catch {
            connection.cancel()
            throw error
        }
        if let metadata = connection.metadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
            let chosen = metadata.selectedSubprotocol, chosen != RemoteContract.subprotocol
        {
            connection.cancel()
            throw FrameSocketError.protocolViolation("subprotocol")
        }
    }

    func receive() async throws -> String {
        let connection = self.connection
        while true {
            let shot = OneShot<Incoming>()
            connection.receiveMessage { content, context, _, error in
                if error != nil {
                    shot.fail(FrameSocketError.closed)
                    connection.cancel()
                    return
                }
                guard
                    let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                        as? NWProtocolWebSocket.Metadata
                else {
                    shot.fail(FrameSocketError.closed)
                    connection.cancel()
                    return
                }
                switch metadata.opcode {
                case .text:
                    guard let text = String(data: content ?? Data(), encoding: .utf8) else {
                        shot.fail(FrameSocketError.protocolViolation("text frame not UTF-8"))
                        connection.cancel()
                        return
                    }
                    shot.succeed(.text(text))
                case .close:
                    shot.fail(FrameSocketError.closed)
                    connection.cancel()
                case .binary:
                    shot.fail(FrameSocketError.protocolViolation("binary frame"))
                    connection.cancel()
                default:
                    shot.succeed(.control)
                }
            }
            switch try await shot.value(onCancel: { connection.cancel() }) {
            case .text(let text): return text
            case .control: continue
            }
        }
    }

    func send(_ text: String) async throws {
        let shot = OneShot<Void>()
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(
            content: Data(text.utf8), contentContext: context, isComplete: true,
            completion: .contentProcessed { error in
                if error != nil { shot.fail(FrameSocketError.closed) } else { shot.succeed(()) }
            })
        try await shot.value()
    }

    func ping() async throws {
        let shot = OneShot<Void>()
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        metadata.setPongHandler(queue) { error in
            if error != nil { shot.fail(FrameSocketError.closed) } else { shot.succeed(()) }
        }
        let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
        connection.send(
            content: Data(), contentContext: context, isComplete: true,
            completion: .contentProcessed { error in
                if error != nil { shot.fail(FrameSocketError.closed) }
            })
        try await shot.value()
    }

    func close() async {
        let first = closing.withLock { closing in
            defer { closing = true }
            return !closing
        }
        guard first else { return }
        let connection = self.connection
        let sent = OneShot<Void>()
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = .protocolCode(.normalClosure)
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        connection.send(
            content: nil, contentContext: context, isComplete: true,
            completion: .contentProcessed { _ in sent.succeed(()) })
        // Let the close frame go out, but never wait long for it.
        let timer = Task {
            try? await Task.sleep(for: .milliseconds(500))
            sent.succeed(())
        }
        _ = try? await sent.value()
        timer.cancel()
        connection.cancel()
    }

    private static func openFailure(_ error: NWError) -> FrameSocketError {
        switch error {
        case .posix(let code): .unreachable("posix \(code.rawValue)")
        case .dns(let code): .unreachable("dns \(code)")
        case .tls(let status): .unreachable("tls \(status)")
        default: .unreachable("network")
        }
    }
}

/// Set by TLS's verify block when the server's key is not the pinned one, so the failure reads as a pin mismatch.
private final class PinCheck: Sendable {
    private let state = Mutex(false)
    func markMismatch() { state.withLock { $0 = true } }
    var mismatched: Bool { state.withLock { $0 } }
}

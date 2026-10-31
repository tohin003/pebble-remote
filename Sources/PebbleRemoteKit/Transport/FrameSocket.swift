import Foundation
import Synchronization

/// One open WebSocket to the bridge, already through TLS (with the pin checked) and the WebSocket upgrade. LiveClient
/// speaks the contract over it; tests drive LiveClient with a fake.
///
/// One reader at a time calls `receive()`. Cancelling the task waiting in `open`, `receive` or `ping` ends that wait
/// (`receive` closes the socket; `ping` does not).
public protocol FrameSocket: AnyObject, Sendable {
    /// The next text frame. Throws `FrameSocketError.closed` once the connection has ended.
    func receive() async throws -> String
    func send(_ text: String) async throws
    /// Sends a WebSocket ping and returns when its pong arrives.
    func ping() async throws
    /// Closes politely (a close frame, then the connection). Safe to call more than once.
    func close() async
}

/// Opens sockets to the bridge's endpoints.
public protocol FrameSocketConnector: Sendable {
    /// Connects to `endpoint` and returns once the WebSocket is open. The TLS server key must hash to `pin`
    /// (contract 3.1); any other key fails with `FrameSocketError.pinMismatch`.
    func open(_ endpoint: Endpoint, pin: String) async throws -> any FrameSocket
}

/// Why a socket could not open or stopped. Content-free: safe to log.
public enum FrameSocketError: Error, Sendable, Hashable {
    /// The connection ended (the bridge closed it, the network dropped it, or it was closed here).
    case closed
    /// The server's TLS key is not the paired Mac's.
    case pinMismatch
    /// No route, refused, or too slow.
    case unreachable(String)
    /// iOS kept the connection on the phone: Pebble Remote may not use the local network (its Local Network switch in
    /// Settings → Privacy & Security is off, or its prompt was declined).
    case localNetworkDenied
    /// Not a WebSocket speaking this contract (a binary frame, a failed upgrade, an oversized message).
    case protocolViolation(String)
}

/// Resumes a continuation exactly once, whichever comes first: a result, an error, or the waiting task's
/// cancellation. Used to bridge Network.framework's callbacks into async calls that cancel properly.
final class OneShot<Value: Sendable>: Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Value, any Error>)
        case finished(Result<Value, any Error>)
        case consumed
    }

    private let state = Mutex<State>(.idle)

    init() {}

    /// Waits for `succeed` or `fail`. `onCancel` runs (once) if the waiting task is cancelled first.
    func value(onCancel: @escaping @Sendable () -> Void = {}) async throws -> Value {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                let ready: Result<Value, any Error>? = state.withLock { state in
                    switch state {
                    case .idle:
                        state = .waiting(continuation)
                        return nil
                    case .finished(let result):
                        state = .consumed
                        return result
                    case .waiting, .consumed:
                        return .failure(CancellationError())
                    }
                }
                if let ready { continuation.resume(with: ready) }
            }
        } onCancel: {
            if finish(.failure(CancellationError())) { onCancel() }
        }
    }

    func succeed(_ value: Value) { finish(.success(value)) }
    func fail(_ error: any Error) { finish(.failure(error)) }

    /// True when this call decided the outcome.
    @discardableResult
    private func finish(_ result: Result<Value, any Error>) -> Bool {
        let (decided, waiting): (Bool, CheckedContinuation<Value, any Error>?) = state.withLock { state in
            switch state {
            case .idle:
                state = .finished(result)
                return (true, nil)
            case .waiting(let continuation):
                state = .consumed
                return (true, continuation)
            case .finished, .consumed:
                return (false, nil)
            }
        }
        waiting?.resume(with: result)
        return decided
    }
}

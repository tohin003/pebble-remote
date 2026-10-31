import Foundation

/// Happy-Eyeballs racing of the Mac's endpoints (contract 3.1): every LAN endpoint starts at once, the others
/// (Tailscale, anything else) 150 ms later, or at once when every LAN attempt has already failed. The first attempt
/// to succeed wins; the rest are cancelled, and any that succeed anyway are handed to `discard` (to close them).
enum EndpointRace {
    /// One endpoint's failure.
    struct Failure: Sendable {
        var endpoint: Endpoint
        var error: any Error
    }

    /// Every endpoint failed.
    struct AllFailed: Error, Sendable {
        var failures: [Failure]
    }

    /// The endpoints in two waves, duplicates removed, order kept within each wave.
    static func waves(_ endpoints: [Endpoint]) -> (first: [Endpoint], later: [Endpoint]) {
        var seen = Set<Endpoint>()
        let unique = endpoints.filter { seen.insert($0).inserted }
        let lan = unique.filter { $0.routeKind == .lan }
        let others = unique.filter { $0.routeKind != .lan }
        return lan.isEmpty ? (others, []) : (lan, others)
    }

    private enum Event<Value: Sendable>: Sendable {
        case timer
        case success(Value, Endpoint)
        case failure(Failure)
    }

    private static func add<Value: Sendable>(
        _ endpoint: Endpoint, to group: inout TaskGroup<Event<Value>>,
        attempt: @escaping @Sendable (Endpoint) async throws -> Value
    ) {
        group.addTask {
            do {
                return .success(try await attempt(endpoint), endpoint)
            } catch {
                return .failure(Failure(endpoint: endpoint, error: error))
            }
        }
    }

    /// Runs `attempt` on each endpoint as described above and returns the first success.
    static func run<Value: Sendable>(
        _ endpoints: [Endpoint], delay: Duration = .milliseconds(150),
        attempt: @escaping @Sendable (Endpoint) async throws -> Value,
        discard: @escaping @Sendable (Value) async -> Void
    ) async throws -> (value: Value, endpoint: Endpoint) {
        let (first, later) = waves(endpoints)
        guard !first.isEmpty else { throw AllFailed(failures: []) }

        let outcome: Result<(Value, Endpoint), AllFailed> = await withTaskGroup(of: Event<Value>.self) { group in
            var running = 0
            var laterStarted = later.isEmpty
            var failures: [Failure] = []

            for endpoint in first {
                add(endpoint, to: &group, attempt: attempt)
                running += 1
            }
            if !laterStarted {
                group.addTask {
                    try? await Task.sleep(for: delay)
                    return .timer
                }
            }

            while let event = await group.next() {
                var startLater = false
                switch event {
                case .timer:
                    startLater = !laterStarted
                case .success(let value, let endpoint):
                    group.cancelAll()
                    while let rest = await group.next() {
                        if case .success(let extra, _) = rest { await discard(extra) }
                    }
                    return .success((value, endpoint))
                case .failure(let failure):
                    failures.append(failure)
                    running -= 1
                    if running == 0 {
                        if laterStarted {
                            group.cancelAll()
                            return .failure(AllFailed(failures: failures))
                        }
                        startLater = true
                    }
                }
                if startLater {
                    laterStarted = true
                    for endpoint in later {
                        add(endpoint, to: &group, attempt: attempt)
                        running += 1
                    }
                }
            }
            return .failure(AllFailed(failures: failures))
        }
        let (value, endpoint) = try outcome.get()
        return (value, endpoint)
    }
}

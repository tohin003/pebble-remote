import Foundation

/// How long to wait before reconnect attempt `n`: exponential from 0.5 s, doubling, capped at 30 s, with ±20 % jitter
/// so retries do not fall into step with anything else on the network.
public struct Backoff: Sendable, Hashable {
    public var initial: Duration
    public var maximum: Duration
    public var multiplier: Double
    /// The largest fraction a delay is moved up or down by (0.2: from 80 % to 120 % of the step, never above
    /// `maximum`).
    public var jitter: Double

    public init(
        initial: Duration = .milliseconds(500), maximum: Duration = .seconds(30), multiplier: Double = 2,
        jitter: Double = 0.2
    ) {
        self.initial = initial
        self.maximum = maximum
        self.multiplier = multiplier
        self.jitter = jitter
    }

    /// The step before jitter for attempt `attempt` (1 is the first retry).
    public func step(attempt: Int) -> Duration {
        let initialSeconds = initial.inSeconds
        let maximumSeconds = maximum.inSeconds
        let exponent = Double(max(0, attempt - 1))
        let seconds = min(maximumSeconds, initialSeconds * pow(multiplier, min(exponent, 64)))
        return .seconds(seconds)
    }

    /// The delay for attempt `attempt`, with `unit` in [0, 1) choosing where in the jitter range it falls (0.5 is no
    /// jitter).
    public func delay(attempt: Int, unit: Double) -> Duration {
        let base = step(attempt: attempt).inSeconds
        let factor = 1 - jitter + 2 * jitter * min(max(unit, 0), 1)
        return .seconds(min(maximum.inSeconds, max(0, base * factor)))
    }

    /// The delay for attempt `attempt`, jittered at random.
    public func delay(attempt: Int) -> Duration {
        delay(attempt: attempt, unit: Double.random(in: 0..<1))
    }
}

extension Duration {
    /// This duration in seconds, as a Double.
    var inSeconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    /// In milliseconds, as a Double.
    var inMilliseconds: Double { inSeconds * 1000 }
}

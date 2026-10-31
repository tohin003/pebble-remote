import PebbleProtocol
import PebbleRemoteKit

/// The settled runs' summaries this session read (`run_activity` past every item), so a line that scrolls away and
/// back doesn't read again. A settled run's summary doesn't change.
enum WorkReceipts {
    static var summaries: [RunID: WorkSummary] = [:]
    /// Runs Pebble has no summary for (nothing worth a line, or it still waits).
    static var none: Set<RunID> = []
}

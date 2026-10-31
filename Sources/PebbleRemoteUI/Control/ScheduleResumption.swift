import PebbleRemoteKit

/// A schedule and what resuming it would run with, waiting for the person's confirmation.
struct ScheduleResumption: Equatable {
    let item: ScheduleItem
    let review: ScheduleReview
}

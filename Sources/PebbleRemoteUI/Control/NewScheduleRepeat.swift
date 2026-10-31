import PebbleDesign
/// How often a new schedule runs (Pebble's schedule kinds: once, daily, interval).
enum NewScheduleRepeat: String, CaseIterable, Identifiable {
    case once, daily, everyFewHours

    var id: Self { self }

    var name: String {
        switch self {
        case .once: AppCopy.NewSchedule.once
        case .daily: AppCopy.NewSchedule.daily
        case .everyFewHours: AppCopy.NewSchedule.everyFewHours
        }
    }
}

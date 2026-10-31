import PebbleDesign
import SwiftUI

/// When a new schedule runs: once at a date and time, every day at a time (this phone's time zone), or every few hours.
struct NewScheduleTimingSection: View {
    @Binding var repeats: NewScheduleRepeat
    @Binding var when: Date
    @Binding var everyHours: Int

    var body: some View {
        Section {
            Picker(AppCopy.NewSchedule.repeats, selection: $repeats) {
                ForEach(NewScheduleRepeat.allCases) { choice in
                    Text(choice.name).tag(choice)
                }
            }
            switch repeats {
            case .once:
                DatePicker(
                    AppCopy.NewSchedule.at, selection: $when,
                    in: Date.now...Date.now.addingTimeInterval(364 * 86_400))
            case .daily:
                DatePicker(AppCopy.NewSchedule.at, selection: $when, displayedComponents: .hourAndMinute)
            case .everyFewHours:
                Stepper(AppCopy.NewSchedule.everyHours(everyHours), value: $everyHours, in: 1...24)
            }
        }
    }
}

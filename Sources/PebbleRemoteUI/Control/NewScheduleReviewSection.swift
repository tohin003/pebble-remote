import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// What Pebble says a new schedule would run with (its mode and model now) and its next times, before Create.
struct NewScheduleReviewSection: View {
    let review: ScheduleReview

    var body: some View {
        Section {
            if let mode = review.mode {
                LabeledContent(AppCopy.Control.permissions, value: ModeCopy.for(mode).name)
            }
            if let model = review.modelName {
                LabeledContent(AppCopy.Control.model, value: model)
            }
            ForEach(review.nextTimes.prefix(3), id: \.self) { time in
                Text(time.formatted(date: .abbreviated, time: .shortened))
                    .monospacedDigit()
            }
        } header: {
            Text(AppCopy.NewSchedule.nextRuns)
        } footer: {
            Text(AppCopy.NewSchedule.reviewNote)
        }
    }
}

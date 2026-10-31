import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One schedule: its name, its conversation, when it runs next, and whether it is paused, waits for review or hit a
/// problem (Pebble's words for the problem).
struct ScheduleRow: View {
    let item: ScheduleItem
    let isWorking: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(item.name)
                    .font(.headline)
                Text(item.chatTitle)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                if let state = stateLine {
                    Text(state)
                        .font(PebbleFont.meta)
                        .foregroundStyle(
                            item.problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(PebbleColor.danger))
                }
            }
            Spacer()
            if isWorking {
                ProgressView()
            }
        }
    }

    private var stateLine: String? {
        if let problem = item.problem { return problem }
        if item.needsReview { return AppCopy.Reviews.needsYourReview }
        if item.isPaused { return AppCopy.Conversation.paused }
        return item.nextRun.map { AppCopy.Schedules.next($0.formatted(date: .abbreviated, time: .shortened)) }
    }
}

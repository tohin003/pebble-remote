import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A new schedule in one of Pebble's conversations: a name, what Pebble does each time, and when (once, every day, or
/// every few hours). Review asks Pebble what it would run with and when; Create (Face ID) appears only after a review
/// of exactly what is shown. Changing anything asks for a new review.
struct NewScheduleSheet: View {
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var chatID: ChatID?
    @State private var name = ""
    @State private var task = ""
    @State private var repeats = NewScheduleRepeat.daily
    @State private var when = Date.now.addingTimeInterval(3600)
    @State private var everyHours = 6
    @State private var review: ScheduleReview?
    @State private var isWorking = false
    @FocusState private var isWritingTask: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppCopy.NewSchedule.conversation, selection: $chatID) {
                        ForEach(store.chats) { chat in
                            Text(chat.title.isEmpty ? AppCopy.Chats.untitled : chat.title).tag(Optional(chat.id))
                        }
                    }
                    // One line: Return ends editing. The task's lines: Return with nothing typed closes the keyboard.
                    TextField(AppCopy.NewSchedule.name, text: $name)
                    TextField(AppCopy.NewSchedule.task, text: $task, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($isWritingTask)
                        .closesKeyboardOnEmptyReturn($task, focus: $isWritingTask)
                }
                NewScheduleTimingSection(repeats: $repeats, when: $when, everyHours: $everyHours)
                if let review {
                    NewScheduleReviewSection(review: review)
                }
            }
            // The keyboard always closes without creating: a scroll closes it, and Cancel stays in the bar.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppCopy.NewSchedule.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel) { dismiss() }
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    if review == nil {
                        Button(AppCopy.NewSchedule.review, action: askForReview)
                            .disabled(!isComplete || isWorking)
                    } else {
                        Button(AppCopy.NewSchedule.create, action: create)
                            .disabled(isWorking)
                    }
                }
            }
            .onChange(of: inputs) { review = nil }
            .onAppear { chatID = chatID ?? store.chats.first?.id }
        }
    }

    /// Everything the review covers; any change asks for a new review.
    private var inputs: [String] {
        [chatID ?? "", name, task, repeats.rawValue, "\(when.timeIntervalSince1970)", "\(everyHours)"]
    }

    private var isComplete: Bool {
        chatID != nil && !trimmed(name).isEmpty && !trimmed(task).isEmpty
    }

    private var spec: ScheduleSpec {
        switch repeats {
        case .once:
            return .once(at: when)
        case .daily:
            // Pebble's fixed "HH:MM" (24-hour) form, an exchange format rather than display text.
            let parts = Calendar.current.dateComponents([.hour, .minute], from: when)
            let pad = { (value: Int) in value < 10 ? "0\(value)" : "\(value)" }
            let time = "\(pad(parts.hour ?? 9)):\(pad(parts.minute ?? 0))"
            return .daily(time: time, timezone: TimeZone.current.identifier)
        case .everyFewHours:
            return .interval(seconds: everyHours * 3600)
        }
    }

    private func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func askForReview() {
        guard let chatID else { return }
        isWorking = true
        let schedule = spec
        Task {
            review = await store.attempt { try await store.previewSchedule(in: chatID, schedule: schedule) }
            isWorking = false
        }
    }

    private func create() {
        guard let chatID, let review else { return }
        isWorking = true
        let schedule = spec, scheduleName = trimmed(name), scheduleTask = trimmed(task)
        Task {
            let made = await store.attempt {
                try await store.createSchedule(
                    in: chatID, name: scheduleName, task: scheduleTask, schedule: schedule, review: review)
            }
            isWorking = false
            if made != nil { dismiss() }
        }
    }
}

import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Resume after "Reached this task's limit.": Pebble's window shows two number fields, "Step limit" (1 to 256) and
/// "Active seconds" (1 to 86,400), filled with 128 and 1,800, and sends them with Resume. The phone does the same in a
/// sheet, and keeps Resume off until both are in Pebble's range.
struct ResumeLimitsSheet: View {
    let task: TaskAttention
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var steps: Int? = RunLimits.resumeDefaults.maxSteps
    @State private var seconds: Int? = RunLimits.resumeDefaults.maxSeconds
    @State private var isSending = false
    @State private var failure: String?
    @State private var resumes = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(RecoveryCopy.Task.sentence(task.state))
                        .font(PebbleFont.cardTitle)
                    if let note = task.note {
                        Text(note)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent(RecoveryCopy.Limits.stepLimit) {
                        numberField(RecoveryCopy.Limits.stepLimit, value: $steps)
                    }
                    LabeledContent(RecoveryCopy.Limits.activeSeconds) {
                        numberField(RecoveryCopy.Limits.activeSeconds, value: $seconds)
                    }
                    if let seconds, RunLimits.secondRange.contains(seconds) {
                        Text(RecoveryCopy.Limits.minutes(seconds))
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                } footer: {
                    Text(RecoveryCopy.Limits.range)
                }
                if failure != nil {
                    Section { SheetFailure(message: failure) }
                }
            }
            // The number pads have no Return key: a scroll closes the keyboard, and Cancel stays in the bar.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(RecoveryCopy.Limits.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel) { dismiss() }
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(RecoveryCopy.Limits.resume, action: resume)
                        .disabled(limits == nil || isSending)
                }
            }
            .sensoryFeedback(PebbleHaptics.stopped, trigger: resumes)
        }
        .formSheetDetents(typeSize)
    }

    /// Both numbers, when Pebble accepts them.
    private var limits: RunLimits? {
        guard let steps, let seconds else { return nil }
        let limits = RunLimits(maxSteps: steps, maxSeconds: seconds)
        return limits.isValid ? limits : nil
    }

    private func numberField(_ title: String, value: Binding<Int?>) -> some View {
        TextField(title, value: value, format: .number)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .frame(minWidth: 88)
    }

    private func resume() {
        guard let limits, !isSending else { return }
        isSending = true
        failure = nil
        let task = self.task
        Task {
            if await store.attempt({ try await store.resume(task, limits: limits) }) {
                resumes += 1
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isSending = false
        }
    }
}

import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Uncertain outcomes" (ReconcilePanel.vue): what Pebble lost track of before it could confirm it, each with Pebble's
/// readback verdict and basis. "Settle from readback" when the readback is clean; otherwise (or as well) the person
/// reports it themselves, "It happened" or "It did not happen" with what they checked, recorded as unverified. Nothing
/// is retried. Once every outcome is settled the task can resume.
struct UncertainOutcomesSheet: View {
    let task: TaskAttention
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var page: ReadbackPage?
    @State private var failure: String?
    @State private var busy: String?
    @State private var reports: [String: OutcomeReport] = [:]
    @State private var notes: [String: String] = [:]
    @State private var settled = 0
    /// The step whose note is being written.
    @FocusState private var focusedNote: String?

    private static let noteLimit = 2000

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(RecoveryCopy.Outcomes.intro)
                        .font(PebbleFont.cardBody)
                }
                if let page {
                    if page.waitsForTask {
                        Section { Text(RecoveryCopy.Outcomes.waitsForTask) }
                    } else if page.items.isEmpty {
                        Section { Text(RecoveryCopy.Outcomes.none) }
                    } else {
                        ForEach(page.items) { item in
                            outcome(item)
                        }
                    }
                }
                if failure != nil {
                    Section { SheetFailure(message: failure) }
                }
            }
            // The keyboard always closes without recording: a scroll closes it, Done stays in the bar, and Return in an
            // empty note drops its focus (`KeyboardRules`).
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if page == nil && failure == nil {
                    ProgressView(RecoveryCopy.Outcomes.reading)
                }
            }
            .disabled(busy != nil)
            .navigationTitle(RecoveryCopy.Outcomes.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Common.done) { dismiss() }
                        .pebbleBarButton()
                }
            }
            .sensoryFeedback(PebbleHaptics.approved, trigger: settled)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func outcome(_ item: UncertainOutcome) -> some View {
        // The step in Pebble's activity words, never its tool or field names (UX audit U-29).
        let label = AppCopy.Steps.name(tool: item.tool, kind: item.kind, app: pausedApp)
        Section {
            Text(RecoveryCopy.Outcomes.verdict(item.verdict))
            if let basis = AppCopy.Steps.basis(item.basis) {
                Text(basis)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            if item.canSettleFromReadback && store.bridgeOffers("run_reconcile") {
                Button(RecoveryCopy.Outcomes.settle) { settle(item) }
                    .accessibilityLabel(AppCopy.Steps.settleLabel(label))
            }
        } header: {
            Text(verbatim: label)
                .textCase(nil)
        }
        if store.bridgeOffers("run_reconcile") {
            Section {
                Picker(RecoveryCopy.Outcomes.reportYourself, selection: report(for: item)) {
                    Text(RecoveryCopy.Outcomes.happened).tag(OutcomeReport?.some(.occurred))
                    Text(RecoveryCopy.Outcomes.didNotHappen).tag(OutcomeReport?.some(.didNotOccur))
                }
                .pickerStyle(.inline)
                .labelsHidden()
                TextField(RecoveryCopy.Outcomes.notePlaceholder, text: note(for: item), axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focusedNote, equals: item.callID)
                    .accessibilityLabel(AppCopy.Steps.whatYouChecked(label))
                Button(RecoveryCopy.Outcomes.record) { record(item) }
                    .disabled(!canRecord(item))
            } header: {
                Text(RecoveryCopy.Outcomes.reportYourself)
                    .textCase(nil)
            }
        }
    }

    /// The app whose window the uncertain step acted in: Pebble pauses the window of a step whose result is uncertain
    /// ("Mail's window is paused…"), so when the task paused exactly one app window, its screen steps were there.
    private var pausedApp: String? {
        let current = store.waiting.lazy.compactMap { item -> TaskAttention? in
            if case .task(let waiting) = item, waiting.id == task.id { return waiting }
            return nil
        }.first ?? task
        return Self.pausedApp(current.pausedWindows)
    }

    static func pausedApp(_ windows: [ScreenSession]) -> String? {
        let apps = windows.filter { $0.kind == "app" }
        guard apps.count == 1 else { return nil }
        return AppCopy.Places.appName(bundleID: apps[0].bundleID)
    }

    private func report(for item: UncertainOutcome) -> Binding<OutcomeReport?> {
        Binding(get: { reports[item.callID] }, set: { reports[item.callID] = $0 })
    }

    private func note(for item: UncertainOutcome) -> Binding<String> {
        Binding(
            get: { notes[item.callID] ?? "" },
            set: { new in
                // Return in an empty note closes the keyboard rather than starting a blank line.
                if KeyboardRules.isEmptyReturn(new) {
                    notes[item.callID] = ""
                    focusedNote = nil
                } else {
                    notes[item.callID] = String(new.prefix(Self.noteLimit))
                }
            })
    }

    /// ReconcilePanel: a choice and a note with words in it.
    private func canRecord(_ item: UncertainOutcome) -> Bool {
        reports[item.callID] != nil && !(notes[item.callID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() async {
        do {
            page = try await store.readback(task)
            failure = nil
        } catch {
            failure = store.takeNotice()
        }
    }

    private func settle(_ item: UncertainOutcome) {
        act(item) { try await store.settleFromReadback(item) }
    }

    private func record(_ item: UncertainOutcome) {
        guard canRecord(item), let report = reports[item.callID] else { return }
        let words = notes[item.callID] ?? ""
        act(item) { try await store.recordReport(item, report, note: words) }
    }

    private func act(_ item: UncertainOutcome, _ work: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = item.callID
        failure = nil
        Task {
            if await store.attempt(work) {
                settled += 1
                reports[item.callID] = nil
                notes[item.callID] = nil
                await load()
            } else {
                failure = store.takeNotice()
            }
            busy = nil
        }
    }
}

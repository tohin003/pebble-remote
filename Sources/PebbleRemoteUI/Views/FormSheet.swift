import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A Pebble form, answered on the phone (contract 3.12; the inventory's item 1: "a question in disguise", which blocks
/// its task). The system's own controls for its 1 to 3 fields, then "Submit answers" (or the form's own words) through
/// `artifact_submit`, which needs the unlock and no Face ID (contract 3.6 doesn't list it). Every field closes its
/// keyboard without sending: Return ends editing, a scroll closes it, and Cancel closes the sheet and sends nothing.
/// A form that no longer waits opens read-only, with the answers Pebble kept.
struct FormSheet: View {
    @State private var artifact: PebbleArtifact
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [String: String] = [:]
    @State private var texts: [String: String] = [:]
    @State private var isBusy = false
    @State private var failure: String?
    @State private var sentCount = 0
    @State private var isConfirmingStop = false
    @FocusState private var focused: String?

    init(artifact: PebbleArtifact) {
        _artifact = State(initialValue: artifact)
        if let form = artifact.form, let given = artifact.formQuestion?.answers {
            let values = FormAnswers.values(form, from: given)
            _choices = State(initialValue: values.choices)
            _texts = State(initialValue: values.texts)
        }
    }

    private var isOpen: Bool { FormAnswers.isOpen(artifact) && store.bridgeOffers("artifact_submit") }

    var body: some View {
        NavigationStack {
            Form {
                FormSheetHeader(artifact: artifact)
                if let form = artifact.form {
                    ForEach(form.fields) { field in
                        FormFieldSection(
                            field: field, choice: choice(for: field.id), text: text(for: field.id),
                            isEnabled: isOpen && !isBusy, focus: $focused)
                    }
                    if isOpen {
                        FormSubmitSection(
                            isBusy: isBusy, isComplete: FormAnswers.make(form, choices: choices, texts: texts) != nil,
                            failure: failure, submit: submit)
                    } else if failure != nil {
                        Section { SheetFailure(message: failure) }  // lane T: a refused Stop
                    }
                } else {
                    Section {
                        UnsupportedViewNote(artifact: artifact)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(artifact.title ?? AppCopy.Views.kind(artifact.kind))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isOpen ? AppCopy.Views.cancel : AppCopy.Views.close, action: close)
                }
                // Lane T (CV-09): Stop view, the form's one rare control, behind ⋯; it asks first.
                if artifact.isLive, store.bridgeOffers("artifact_stop") {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(AppCopy.ViewHistory.stop, systemImage: "stop.circle", role: .destructive) {
                                isConfirmingStop = true
                            }
                        } label: {
                            Label(AppCopy.ViewHistory.more, systemImage: "ellipsis.circle")
                        }
                        .disabled(isBusy)
                    }
                }
            }
            .task { await refresh() }
        }
        .sensoryFeedback(PebbleHaptics.sent, trigger: sentCount)
        .interactiveDismissDisabled(isBusy)
        .confirmationDialog(AppCopy.ViewHistory.stopTitle, isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button(AppCopy.ViewHistory.stop, role: .destructive, action: stop)
        } message: {
            Text(AppCopy.ViewHistory.stopMessage(waitingForm: artifact.waitsForAnswer))
        }
    }

    /// Lane T: Stop view, once the person confirmed. The form comes back stopped and read-only ("This form is
    /// stopped."); Pebble's refusal shows here.
    private func stop() {
        guard !isBusy else { return }
        focused = nil
        isBusy = true
        failure = nil
        let view = artifact
        Task {
            if let stopped = await store.attempt({ try await store.stopView(view) }) {
                artifact = stopped
            } else {
                failure = store.takeNotice()
            }
            isBusy = false
        }
    }

    /// A field's value in the form's answers (each field has its own entry, so no view keeps a copy).
    private func choice(for id: String) -> Binding<String?> {
        Binding(get: { choices[id] }, set: { choices[id] = $0 })
    }

    private func text(for id: String) -> Binding<String> {
        Binding(get: { texts[id] ?? "" }, set: { texts[id] = $0 })
    }

    private func close() {
        focused = nil
        dismiss()
    }

    /// The form as Pebble keeps it now (ArtifactPanel.vue reads it again when it opens): a newer revision, or one that
    /// was answered or stopped meanwhile. What the person chose so far stays.
    private func refresh() async {
        guard store.bridgeOffers("artifact_get"), let fresh = try? await store.readView(artifact.id, in: artifact.chatID),
            fresh != artifact
        else { return }
        artifact = fresh
        if !FormAnswers.isOpen(fresh), let form = fresh.form, let given = fresh.formQuestion?.answers, !given.isEmpty {
            let values = FormAnswers.values(form, from: given)
            choices = values.choices
            texts = values.texts
        }
    }

    private func submit() {
        guard let form = artifact.form, !isBusy else { return }
        guard let answers = FormAnswers.make(form, choices: choices, texts: texts) else {
            failure = AppCopy.Views.completeEveryField
            return
        }
        focused = nil
        isBusy = true
        failure = nil
        let view = artifact
        Task {
            if await store.attempt({ try await store.submit(answers, to: view) }) {
                sentCount += 1
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isBusy = false
        }
    }
}

import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A memory added by hand to one layer, as Pebble's "Add {layer}" form saves it (AdvancedSettings.vue): the words (up
/// to 4,000 characters, where the Mac's field stops too), the recall scope, and for time-sensitive information when it
/// expires. The Mac's second scope is "Current conversation's connected project"; Settings on the phone belong to no
/// conversation, so the person picks the project by name. Pebble's refusals ("Memory is off for this layer.") show in
/// the sheet, where the person is.
struct AddMemorySheet: View {
    let layer: MemoryLayer
    /// Called once Pebble saved it.
    let saved: () -> Void
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text = ""
    @State private var recall = MemoryRecall.personal
    @State private var expires = Date.now.addingTimeInterval(86_400)
    @State private var isSaving = false
    @State private var failure: String?
    @FocusState private var isWriting: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.Learning.placeholder, text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($isWriting)
                        .closesKeyboardOnEmptyReturn($text, focus: $isWriting)
                } header: {
                    Text(AppCopy.Learning.addLayer(layer.name))
                } footer: {
                    if text.count >= MemoryLayers.longest {
                        Text(AppCopy.Learning.atLimit)
                    }
                }
                Section {
                    if store.projects.isEmpty {
                        LabeledContent(AppCopy.Learning.recallScope, value: AppCopy.Learning.personal)
                    } else {
                        Picker(AppCopy.Learning.recallScope, selection: $recall) {
                            Text(AppCopy.Learning.personal).tag(MemoryRecall.personal)
                            ForEach(store.projects) { project in
                                Text(AppCopy.Learning.project(project.name)).tag(MemoryRecall.project(project))
                            }
                        }
                    }
                }
                if layer.id == MemoryLayers.timeSensitive {
                    Section {
                        DatePicker(
                            AppCopy.Learning.expiresAt, selection: $expires, in: Date.now...,
                            displayedComponents: [.date, .hourAndMinute])
                    }
                }
                if failure != nil {
                    Section { SheetFailure(message: failure) }
                }
            }
            // The keyboard always closes without saving: a scroll closes it, and Cancel stays in the bar.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppCopy.Learning.newMemory)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel) { dismiss() }
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Learning.save, action: save)
                        .disabled(!canSave)
                }
            }
            .onChange(of: text) { _, typed in
                // Pebble keeps 4,000 characters; the Mac's field takes no more, and neither does this one.
                if typed.count > MemoryLayers.longest { text = String(typed.prefix(MemoryLayers.longest)) }
            }
        }
        .formSheetDetents(typeSize)
    }

    private var canSave: Bool {
        !isSaving && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        failure = nil
        let words = text, layer = layer.id, recall = recall
        let expiry = layer == MemoryLayers.timeSensitive ? expires : nil
        Task {
            if await store.attempt({ try await store.saveMemory(words, in: layer, recall: recall, expires: expiry) }) {
                saved()
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isSaving = false
        }
    }
}

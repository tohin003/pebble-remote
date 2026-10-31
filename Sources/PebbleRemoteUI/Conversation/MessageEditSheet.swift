import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Edit your message" from a long press on the person's last message: Pebble's editor as a sheet. The words come back to
/// change, and Send sends them as a new message; the old one stays as it was (App.vue's ".message-editor"). The keyboard
/// closes with Cancel, a swipe down the form, or Return in an empty field, never only by sending.
struct MessageEditSheet: View {
    /// Sends the edited words; returns whether Pebble took them.
    let send: (String) async -> Bool
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var text: String
    @State private var isSending = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    init(original: String, send: @escaping (String) async -> Bool) {
        self.send = send
        _text = State(initialValue: original)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.MessageMenu.editField, text: $text, axis: .vertical)
                        .lineLimit(3...12)
                        .focused($isFocused)
                        .closesKeyboardOnEmptyReturn($text, focus: $isFocused)
                        .accessibilityLabel(AppCopy.MessageMenu.editField)
                } footer: {
                    Text(AppCopy.MessageMenu.editNote)
                }
                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppCopy.MessageMenu.editTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel, action: close)
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    // One word, so the title fits between the buttons; VoiceOver hears Pebble's "Send edited".
                    Button(AppCopy.MessageMenu.send, action: sendEdited)
                        .disabled(isSending || trimmed.isEmpty || !store.bridgeOffers("send"))
                        .accessibilityLabel(AppCopy.MessageMenu.sendEdited)
                }
            }
            .onAppear { isFocused = true }
        }
        .formSheetDetents(typeSize)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func close() {
        dismiss()
    }

    private func sendEdited() {
        let words = trimmed
        guard !words.isEmpty, !isSending else { return }
        isSending = true
        failure = nil
        Task {
            if await send(words) {
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isSending = false
        }
    }
}

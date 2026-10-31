import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Read a web source" (Pebble's dialog, "Read a web page"), in Pebble's words: a public HTTPS page Pebble reads as
/// source material for the next message. In a new conversation Pebble reads it when the first message is sent.
struct WebSourceSheet: View {
    /// A new conversation: nothing is read before its first message.
    let readsOnSend: Bool
    /// Keeps the address for the next message; returns whether it was taken.
    let attach: (String) async -> Bool
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var isReading = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.WebSource.placeholder, text: $address)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(attachSource)
                        .accessibilityLabel(AppCopy.WebSource.field)
                        .focused($isFocused)
                } header: {
                    Text(AppCopy.WebSource.intro)
                        .textCase(nil)
                } footer: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        Text(AppCopy.WebSource.note)
                        if readsOnSend {
                            Text(AppCopy.WebSource.readsOnSend)
                        }
                    }
                }
                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
            }
            .navigationTitle(AppCopy.WebSource.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel, action: close)
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    // One word, so the title fits between the buttons (UX audit U-47, as U-27); VoiceOver hears
                    // Pebble's words.
                    Button(isReading ? AppCopy.WebSource.reading : AppCopy.SheetActions.attach, action: attachSource)
                        .disabled(isReading || trimmed.isEmpty)
                        .accessibilityLabel(isReading ? AppCopy.WebSource.reading : AppCopy.WebSource.attach)
                        .accessibilityIdentifier(AppCopy.WebSource.attach)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func close() {
        dismiss()
    }

    private func attachSource() {
        let words = trimmed
        guard !words.isEmpty, !isReading else { return }
        isReading = true
        failure = nil
        Task {
            if await attach(words) {
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isReading = false
        }
    }
}

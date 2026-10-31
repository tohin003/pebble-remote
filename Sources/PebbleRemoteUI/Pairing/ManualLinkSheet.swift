import PebbleDesign
import SwiftUI

/// Typing or pasting the pairing link into a field, for when Universal Clipboard and the camera aren't at hand.
struct ManualLinkSheet: View {
    let flow: PairingFlow
    @Environment(PebbleRemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.Pairing.linkPlaceholder, text: $text, axis: .vertical)
                        .lineLimit(2...6)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .submitLabel(.go)
                        .onSubmit(pair)
                } footer: {
                    Text(AppCopy.Pairing.howTo)
                }
                if let problem = flow.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
            }
            .navigationTitle(AppCopy.Pairing.enterByHand)
            // Once the phone has sent the pairing, the pairing screen shows the code to compare with the Mac's (X-1).
            .onChange(of: flow.code) { _, code in
                if code != nil { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Chats.cancel, role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Pairing.pairButton, action: pair)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || flow.isPairing)
                }
            }
        }
    }

    private func pair() {
        Task {
            await flow.pair(text: text, model: model)
            if flow.problem == nil { dismiss() }
        }
    }
}

import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A pairing link opened from outside the app (the Camera app, a tapped link) pairs only after the person confirms
/// it here: a web page could open such a link too. Once the phone has sent its pairing, the sheet shows the six digits
/// to compare with the Mac's while the person confirms there (X-1); Cancel leaves that wait.
struct PairingConfirmSheet: View {
    let pending: PendingPairing
    @Environment(PebbleRemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var flow = PairingFlow()

    var body: some View {
        NavigationStack {
            Group {
                if let code = flow.code {
                    ScrollView {
                        PairingCodePanel(code: code, showsCancel: false, cancel: cancel)
                            .padding()
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    form
                }
            }
            .navigationTitle(flow.code == nil ? AppCopy.Pairing.confirm(pending.link.macName) : AppCopy.Pairing.codeTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Chats.cancel, role: .cancel, action: cancel)
                }
                if flow.code == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppCopy.Pairing.pairButton, action: pair)
                            .disabled(flow.isPairing)
                    }
                }
            }
        }
        // Leaving the sheet any way at all leaves the wait for the Mac too (a swipe down, or a lock cover taking over).
        .onDisappear { flow.cancel() }
        .lockCover()
    }

    private var form: some View {
        Form {
            Section {
                Label(pending.link.macName, systemImage: PebbleSymbol.mac)
                    .font(.headline)
                ForEach(pending.link.endpoints, id: \.self) { endpoint in
                    Text(endpoint.description)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(AppCopy.Pairing.confirmNote)
            }
            if let warning = Self.warning(for: pending.link.relation(to: model.store.pairedMac)) {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle")
                }
            }
            if let problem = flow.problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(PebbleColor.danger)
                }
            }
        }
    }

    private func pair() {
        Task {
            await flow.pair(pending.link, model: model)
            if flow.problem == nil { dismiss() }
        }
    }

    /// Leaves the wait for the Mac, if there is one, and the sheet.
    private func cancel() {
        flow.cancel()
        dismiss()
    }

    /// What the person must know before this link replaces the pairing they have. A link with the paired Mac's id
    /// but another key gets the strongest words: the id is no secret on the network, and pairing would replace the
    /// keys that work (security review 2026-10-30, S-04).
    static func warning(for relation: PairingLink.Relation) -> String? {
        switch relation {
        case .firstPairing, .samePairedMac: nil
        case .replaces(let current): AppCopy.Pairing.confirmReplaces(current.name)
        case .sameMacNewKey(let current): AppCopy.Pairing.confirmNewKey(current.name)
        }
    }
}

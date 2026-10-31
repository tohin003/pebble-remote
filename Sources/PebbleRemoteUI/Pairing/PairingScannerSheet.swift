#if os(iOS)
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The scanner in a sheet: the camera full width, a hint, Cancel. A code that is a pairing link pairs at once;
/// anything else shows why and keeps scanning.
struct PairingScannerSheet: View {
    let flow: PairingFlow
    @Environment(PebbleRemoteModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var notALink = false

    var body: some View {
        NavigationStack {
            PairingCodeScanner(onCode: found)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom) {
                    // Regular glass on the hint itself, over the camera (design review A4: no material bar).
                    Text(notALink ? AppCopy.Pairing.notALink : AppCopy.Pairing.scanHint)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .padding()
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                        .padding()
                }
                .navigationTitle(AppCopy.Pairing.scanTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppCopy.Chats.cancel, role: .cancel) { dismiss() }
                    }
                }
        }
    }

    private func found(_ text: String) {
        guard let link = PairingLink(string: text) else {
            notALink = true
            return
        }
        dismiss()
        Task { await flow.pair(link, model: model) }
    }
}
#endif

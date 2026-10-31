import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The paired Mac and "Forget this Mac", confirmed first. Forgetting also removes this phone from the Mac when it can.
struct PairedMacSection: View {
    let mac: PairedMac
    @Environment(PebbleRemoteModel.self) private var model
    @State private var isConfirming = false
    @State private var isForgetting = false

    var body: some View {
        Section(AppCopy.Settings.pairedMac) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Label(mac.name, systemImage: PebbleSymbol.mac)
                    .font(.headline)
                Text(AppCopy.Settings.pairedOn(mac.pairedAt))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(AppCopy.Settings.forgetMac, systemImage: "trash", role: .destructive) {
                isConfirming = true
            }
            .disabled(isForgetting)
            .confirmationDialog(
                AppCopy.Settings.forgetMac, isPresented: $isConfirming, titleVisibility: .visible
            ) {
                Button(AppCopy.Settings.forgetConfirmButton, role: .destructive, action: forget)
            } message: {
                Text(AppCopy.Settings.forgetConfirm)
            }
        }
    }

    private func forget() {
        isForgetting = true
        Task {
            await model.forgetMac()
            isForgetting = false
        }
    }
}

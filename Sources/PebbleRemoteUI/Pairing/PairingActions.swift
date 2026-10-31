import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The three ways to bring the Mac's link in: paste it (Universal Clipboard), scan the code (iPhone camera), or type it.
struct PairingActions: View {
    let flow: PairingFlow
    @Binding var isScanning: Bool
    @Binding var isEnteringByHand: Bool
    @Environment(PebbleRemoteModel.self) private var model

    var body: some View {
        VStack {
            PasteButton(payloadType: String.self, onPaste: Self.onPaste(flow: flow, model: model))
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .controlSize(.large)
                .accessibilityHint(AppCopy.Pairing.pasteHint)
            Text(AppCopy.Pairing.pasteHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)  // the Paste button's hint already says it (design review, pairing 3)
            #if os(iOS)
            if PairingCodeScanner.isSupported {
                Button(AppCopy.Pairing.scanCode, systemImage: PebbleSymbol.scan, action: startScanning)
                    .buttonStyle(.pebbleGlass)
                    .controlSize(.large)
            }
            #endif
            Button(AppCopy.Pairing.enterByHand, systemImage: "keyboard") {
                isEnteringByHand = true
            }
            .buttonStyle(.pebbleGlass)
            .controlSize(.large)
        }
        .disabled(flow.isPairing)
    }

    /// PasteButton may call its handler off the main thread, so the handler is Sendable and hops to the main actor.
    private static func onPaste(flow: PairingFlow, model: PebbleRemoteModel) -> @Sendable ([String]) -> Void {
        { strings in
            guard let text = strings.first else { return }
            Task { @MainActor in
                await flow.pair(text: text, model: model)
            }
        }
    }

    #if os(iOS)
    private func startScanning() {
        Task {
            if await PairingCodeScanner.requestCamera() {
                isScanning = true
            } else {
                flow.problem = AppCopy.Pairing.cameraUnavailable
            }
        }
    }
    #endif
}

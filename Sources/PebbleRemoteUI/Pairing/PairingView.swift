import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Before pairing: what to do on the Mac, then paste the link (Universal Clipboard), scan the code, or type the link.
/// "Try the demo" runs a simulated Pebble on the phone. Once the phone has sent its pairing, the screen shows the six
/// digits to compare with the Mac's, while the person confirms there (X-1).
struct PairingView: View {
    @Environment(PebbleRemoteModel.self) private var model
    @State private var flow = PairingFlow()
    @State private var isScanning = false
    @State private var isEnteringByHand = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    if let code = flow.code {
                        PairingCodePanel(code: code, cancel: flow.cancel)
                    } else {
                        PairingHeader()
                        PairingActions(
                            flow: flow, isScanning: $isScanning, isEnteringByHand: $isEnteringByHand)
                        if flow.isPairing {
                            ProgressView(AppCopy.Pairing.pairing)
                        }
                        if let problem = flow.problem {
                            Label(problem, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(PebbleColor.danger)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                // Not while a pairing runs: the demo would replace the store the pairing is for.
                if !flow.isPairing {
                    DemoButton(action: model.startDemo)
                }
            }
            .sheet(isPresented: $isEnteringByHand) {
                ManualLinkSheet(flow: flow)
                    .lockCover()
            }
            #if os(iOS)
            .sheet(isPresented: $isScanning) {
                PairingScannerSheet(flow: flow)
                    .lockCover()
            }
            #endif
        }
    }
}

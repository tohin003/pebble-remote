import PebbleDesign
import PebbleRemoteKit

extension PebbleRemoteModel {
    /// The app's model as the app target makes it: the live store for the paired Mac (lane B's client with its keys in
    /// the Secure Enclave, the pairing kept in the Keychain) and the in-app demo (lane A's simulated Pebble).
    /// - Parameter startInDemo: start in the demo (the `-demo` launch argument).
    public static func standard(startInDemo: Bool = false) -> PebbleRemoteModel {
        PebbleRemoteModel(
            live: {
                RemoteStore(
                    client: LiveClient.standard(pairingReason: { mac in AppCopy.FaceID.pair(mac) }),
                    macStore: KeychainPairedMacStore(), unsent: UnsentText(file: UnsentText.standardFile))
            },
            demo: { RemoteStore.demo() },
            startInDemo: startInDemo)
    }
}

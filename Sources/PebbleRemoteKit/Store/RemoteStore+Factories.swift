import Foundation

extension RemoteStore {
    /// The app's store: Pebble on the paired Mac through its bridge (LiveClient: keys in the Secure Enclave, Face ID
    /// for approvals), with the paired Mac kept in the Keychain. `pairedMac` is nil until the person pairs.
    /// `pairingReason` is the sentence Face ID shows when pairing, given the Mac's name (PebbleDesign's copy, so the
    /// app passes it in). Unsent words are kept in the app's own file (UnsentText).
    public static func live(pairingReason: @escaping @Sendable (String) -> String) -> RemoteStore {
        RemoteStore(
            client: LiveClient.standard(pairingReason: pairingReason), macStore: KeychainPairedMacStore(),
            unsent: UnsentText(file: UnsentText.standardFile))
    }

    /// The in-app demo: a simulated Pebble (DemoClient), paired with the demo's Mac. `pace` scales its pauses: 1 is
    /// lifelike, 0 is for tests and previews that should not wait.
    public static func demo(pace: Double = 1) -> RemoteStore {
        RemoteStore(client: DemoClient(pace: pace), pairedMac: DemoClient.pairedMac(), isDemo: true)
    }
}

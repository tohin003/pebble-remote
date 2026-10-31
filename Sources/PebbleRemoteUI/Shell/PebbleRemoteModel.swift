import Observation
import PebbleRemoteKit
import SwiftUI

/// The app's one model, owned by the app target's `@main` type: which store runs (the paired Mac, or the in-app
/// demo), the Face ID lock, and where the person is. The app target makes it with two factories from
/// PebbleRemoteKit and forwards scene-phase changes to it; everything else happens below `PebbleRemoteRoot`.
@Observable
public final class PebbleRemoteModel {
    /// The store the screens read. Replaced when the demo starts or ends.
    public private(set) var store: RemoteStore
    let router = Router()
    let lock = AppLock()

    @ObservationIgnored private let makeLive: () -> RemoteStore
    @ObservationIgnored private let makeDemo: () -> RemoteStore
    @ObservationIgnored private var phase: ScenePhase = .background

    /// - Parameters:
    ///   - live: makes the store for the paired Mac (the paired Mac comes from the Keychain; nil until paired).
    ///   - demo: makes a store running the simulated Pebble.
    ///   - startInDemo: start in the demo (screenshots, a launch argument).
    public init(
        live: @escaping () -> RemoteStore, demo: @escaping () -> RemoteStore, startInDemo: Bool = false
    ) {
        makeLive = live
        makeDemo = demo
        store = startInDemo ? demo() : live()
        lock.lock(applies: lockApplies)  // the app opens locked: nothing is connected yet, so no unlock to end
        lock.unlockWithBridge = { [weak self] in
            guard let self else { return nil }
            return await self.unlockBridge()
        }
        lock.onLocked = { [weak self] in self?.endBridgeUnlock() }
    }

    /// One fixed store, for previews and tests.
    public convenience init(store: RemoteStore) {
        self.init(live: { store }, demo: { store })
    }

    // MARK: Scene lifecycle

    /// Call from the app's `onChange(of: scenePhase, initial: true)`.
    public func scenePhaseChanged(_ newPhase: ScenePhase) {
        phase = newPhase
        switch newPhase {
        case .active:
            store.start()
            lock.sceneBecameActive()
        case .background:
            // Ends the Mac's unlock first (S-05), then closes the connection; the lock then covers the screen.
            store.stop()
            lock.sceneEnteredBackground(applies: lockApplies)
        default:
            break
        }
    }

    /// The lock protects a paired Mac; before pairing and in the demo there is nothing to protect.
    var lockApplies: Bool { store.pairedMac != nil && !store.isDemo }

    /// The app lock engaged: the Mac's unlock ends with it (S-05), so what the passcode or Face ID lets in never meets an
    /// unlock the last use left behind. Going to the background does it too, through `store.stop()`; the store shares
    /// the one call.
    private func endBridgeUnlock() {
        let store = self.store
        Task { await store.lock() }
    }

    /// The app lock's Face ID, through the bridge's unlock (C1) when connected to a bridge that uses one: one Face ID
    /// covers both. Nil hands back to the device's own check (not connected yet, or the call failed for another reason).
    private func unlockBridge() async -> Bool? {
        guard store.usesUnlock, store.isConnectedToMac else { return nil }
        do {
            try await store.unlock()
            return true
        } catch RemoteCallError.cancelledByPerson {
            return false
        } catch {
            store.notice = nil  // the device's own check follows; the store's notice for this would only confuse
            return nil
        }
    }

    // MARK: Demo and pairing

    func startDemo() {
        replaceStore(with: makeDemo())
    }

    func leaveDemo() {
        replaceStore(with: makeLive())
    }

    /// Pairs on the live store (leaving the demo first, if it is running). `showingCode` gets the six digits to compare
    /// with the Mac's once the phone has sent its signatures (X-1); the person confirms on the Mac, which takes up to two
    /// minutes. Cancelling the calling task is the person leaving.
    func pair(
        using link: PairingLink, deviceName: String, showingCode: @escaping @Sendable (PairingCode) -> Void = { _ in }
    ) async throws {
        if store.isDemo { replaceStore(with: makeLive()) }
        try await store.pair(using: link, deviceName: deviceName, showingCode: showingCode)
        router.reset()
    }

    /// Forgets the Mac: the store removes this phone from the Mac and the Keychain; the root shows Pairing.
    func forgetMac() async {
        await store.forgetMac()
        router.reset()
        lock.release()
    }

    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        router.open(link)
    }

    private func replaceStore(with next: RemoteStore) {
        store.stop()
        store = next
        router.reset()
        lock.release()
        if phase == .active { store.start() }
    }
}

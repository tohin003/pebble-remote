import PebbleRemoteKit
import SwiftUI

/// The Mac screen, wired to the store's `screenshot(display:)` (contract C3). A failure shows inside the view (the Mac's
/// own words, such as a missing Screen Recording permission), so the store's notice for it is cleared, not shown twice.
struct MacScreenDestination: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        MacScreenView(load: load, stealth: store.pebble?.stealth ?? false)
    }

    private func load(_ display: Int?) async throws -> MacScreenCapture {
        do {
            return MacScreenCapture(try await store.screenshot(display: display))
        } catch {
            store.notice = nil
            throw error
        }
    }
}

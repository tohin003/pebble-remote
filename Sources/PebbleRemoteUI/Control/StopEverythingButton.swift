import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Stops every live run, after a confirmation attached to the button itself.
struct StopEverythingButton: View {
    @Environment(RemoteStore.self) private var store
    @State private var isConfirming = false
    @State private var stops = 0

    var body: some View {
        Button(AppCopy.Control.stopEverything, systemImage: "stop.circle", role: .destructive) {
            isConfirming = true
        }
        .disabled(store.liveRuns.isEmpty)
        .confirmationDialog(
            AppCopy.Control.stopEverythingConfirm, isPresented: $isConfirming, titleVisibility: .visible
        ) {
            Button(AppCopy.Control.stopEverything, role: .destructive, action: stopEverything)
        } message: {
            Text(AppCopy.Control.stopEverythingNote)
        }
        .sensoryFeedback(PebbleHaptics.stoppedEverything, trigger: stops)
    }

    private func stopEverything() {
        Task {
            if await store.attempt({ try await store.stopEverything() }) {
                stops += 1
            }
        }
    }
}

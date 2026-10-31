import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// C1, wired to the store: lane D's UnlockPrompt with the minutes left in the bridge's unlock (ticking), or Locked with
/// Unlock, which asks for Face ID through `store.unlock()`. Reading never needs it; acting does, and the client also
/// asks by itself when a call needs it.
struct UnlockStatusRow: View {
    @Environment(RemoteStore.self) private var store
    @State private var isUnlocking = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            UnlockPrompt(remainingMinutes: minutesLeft(at: context.date), onUnlock: unlock)
        }
        .disabled(isUnlocking)
    }

    private func minutesLeft(at now: Date) -> Int? {
        guard let until = store.unlockedUntil, until > now else { return nil }
        return Int((until.timeIntervalSince(now) / 60).rounded(.up))
    }

    private func unlock() {
        guard !isUnlocking else { return }
        isUnlocking = true
        Task {
            await store.attempt { try await store.unlock() }
            isUnlocking = false
        }
    }
}

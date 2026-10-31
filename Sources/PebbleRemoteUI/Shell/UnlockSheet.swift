import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Shown when a call came back `unlock_required` even after the client's own Face ID retry: what the unlock is, and
/// Unlock. It closes by itself once the bridge is unlocked.
struct UnlockSheet: View {
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    UnlockStatusRow()
                } footer: {
                    Text("\(AppCopy.Unlock.required) \(AppCopy.Unlock.explanation(minutes: store.unlockMinutes))")
                }
            }
            .navigationTitle(AppCopy.Unlock.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel) { dismiss() }
                        .pebbleBarButton()
                }
            }
        }
        .presentationDetents([.medium])
        .onChange(of: store.unlockedUntil) {
            if store.isUnlocked { dismiss() }
        }
    }
}

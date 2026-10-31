import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The efforts the model in use offers, in Pebble's order; choosing one sets it (`model_effort`).
struct EffortList: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        ChoiceList(
            title: AppCopy.Control.effort,
            choices: efforts.map { level in
                Choice(
                    id: level, title: AppCopy.Control.effortName(level),
                    detail: level == store.pebble?.defaultEffort && level != "default" ? AppCopy.Control.recommended : nil)
            },
            selected: store.pebble?.effort,
            choose: choose
        )
        .task { await store.loadControlLists() }
    }

    /// The model in use's efforts as Pebble's state lists them (its window's menu reads the same), else its profile's.
    private var efforts: [String] {
        let current = store.pebble?.efforts ?? []
        return current.isEmpty ? store.models.first { $0.id == store.currentModelID }?.efforts ?? [] : current
    }

    private func choose(_ effort: String) async -> Bool {
        await store.attempt { try await store.setEffort(effort) }
    }
}

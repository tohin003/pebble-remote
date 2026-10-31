import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's model profiles; choosing one makes Pebble use it (`model_select`; Pebble refuses while a task runs). The
/// rows are ChoiceList's (a checkmark on the Mac's choice, progress on the one changing). Lane S (SM-10): when the
/// model in use is a model file on the Mac, its row is followed by Pebble's "Rest Model" or "Load Now", as the Mac's
/// Models tab offers them; they wait while a task runs, and while the model loads.
struct ModelsList: View {
    @Environment(RemoteStore.self) private var store
    @State private var changing: String?

    var body: some View {
        Form {
            Section {
                ForEach(store.models) { model in
                    // "On this device" is Pebble's word for the Mac itself; on the phone it says "On your Mac" (U-37).
                    let place = AppCopy.ModelPlace.provider(model.provider)
                    ChoiceRow(
                        choice: Choice(id: model.id, title: model.name, detail: place),
                        isSelected: model.id == store.currentModelID, isChanging: changing == model.id
                    ) {
                        choose(model.id)
                    }
                    if model.id == store.currentModelID, let state = store.pebble?.localModelState {
                        LocalModelRow(state: state, modelName: model.name)
                    }
                }
            }
        }
        .disabled(changing != nil)
        .navigationTitle(AppCopy.Control.model)
        .sensoryFeedback(PebbleHaptics.selection, trigger: store.currentModelID)
        .overlay {
            if store.models.isEmpty {
                ContentUnavailableView(
                    AppCopy.Control.model, systemImage: PebbleSymbol.model,
                    description: Text(AppCopy.Control.noModel))
            }
        }
        .task { await store.loadControlLists() }
    }

    private func choose(_ id: String) {
        guard id != store.currentModelID, changing == nil else { return }
        changing = id
        Task {
            await store.attempt { try await store.selectModel(id) }
            changing = nil
        }
    }
}

/// "Rest Model" while the model file is loaded, "Load Now" otherwise (`model_unload`, `model_load`), with progress
/// while Pebble loads it. Pebble refuses to rest it while a task runs; both wait then, as on the Mac.
private struct LocalModelRow: View {
    let state: String
    let modelName: String
    @Environment(RemoteStore.self) private var store
    @State private var isSending = false

    var body: some View {
        let isReady = state == "ready"
        let isLoading = state == "loading"
        let method = isReady ? "model_unload" : "model_load"
        if store.bridgeOffers(method) {
            Button {
                send(rest: isReady)
            } label: {
                HStack {
                    Label(
                        isReady ? AppCopy.LocalModel.rest : AppCopy.LocalModel.load,
                        systemImage: isReady ? "moon.zzz" : "bolt.horizontal")
                    if isSending || isLoading {
                        Spacer()
                        ProgressView()
                    }
                }
                .contentShape(.rect)
            }
            .disabled(store.isPebbleWorking || isLoading || isSending)
            .accessibilityHint(store.isPebbleWorking ? AppCopy.LocalModel.idleOnly : modelName)
        }
    }

    private func send(rest: Bool) {
        guard !isSending else { return }
        isSending = true
        Task {
            await store.attempt {
                if rest {
                    try await store.restLocalModel()
                } else {
                    try await store.loadLocalModel()
                }
            }
            isSending = false
        }
    }
}

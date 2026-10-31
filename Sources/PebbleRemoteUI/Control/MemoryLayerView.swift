import Accessibility
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One memory layer, as the Mac's layer tab shows it (AdvancedSettings.vue): "Learning and recall in this layer", then
/// what Pebble saved there, newest first, each in words with where it came from. Search this layer, Load More, and
/// Forget (a swipe or a long press; asked once, then Face ID, as the bridge asks it), which waits while a task runs as
/// Pebble's own button does. The search field's Cancel and a swipe down the list close the keyboard. A layer the person
/// can add to (not working context or past experiences, which Pebble records itself) has "Add {layer}" in the bar, as
/// the Mac's form under the list (lane S, SY-16).
struct MemoryLayerView: View {
    let layerID: String
    @Environment(RemoteStore.self) private var store
    @State private var records: [MemoryRecord] = []
    @State private var hasMore = false
    @State private var isLoaded = false
    @State private var query = ""
    /// The search the list shows; empty when it shows everything.
    @State private var searched = ""
    @State private var forgetting: MemoryRecord?
    @State private var isConfirmingForget = false
    @State private var isAdding = false

    var body: some View {
        List {
            if let layer {
                Section {
                    RemoteToggle(
                        AppCopy.Memories.layerSwitch, value: layer.isOn,
                        faceID: store.faceIDRule(forSetting: "memory_layers")
                    ) { on in
                        await store.attempt { try await store.setMemoryLayer(layer.id, on: on) }
                    }
                    .disabled(!(store.settings?.memoryEnabled ?? true))
                }
            }
            if store.bridgeOffers("memory_list") {
                Section {
                    ForEach(shown) { record in
                        MemoryRow(record: record, chatTitle: chatTitle(record.chatID))
                            .swipeActions(edge: .trailing) {
                                if canForget {
                                    Button(AppCopy.Memories.forget, systemImage: "trash", role: .destructive) {
                                        ask(record)
                                    }
                                }
                            }
                            .contextMenu {
                                Button(AppCopy.Memories.copy, systemImage: "doc.on.doc") {
                                    MessageClipboard.copy(words(record))
                                }
                                if canForget {
                                    Button(AppCopy.Memories.forget, systemImage: "trash", role: .destructive) {
                                        ask(record)
                                    }
                                }
                            }
                    }
                    if isLoaded && shown.isEmpty {
                        Text(searched.isEmpty ? AppCopy.Memories.nothingSaved : AppCopy.Memories.noMatch(searched))
                            .foregroundStyle(.secondary)
                    }
                    if hasMore {
                        Button(AppCopy.Memories.loadMore) { Task { await loadMore() } }
                    }
                } header: {
                    Text(AppCopy.Memories.saved)
                } footer: {
                    if store.isPebbleWorking && store.bridgeOffers("memory_delete") {
                        Text(AppCopy.Memories.idleOnly)
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $query, prompt: AppCopy.Memories.searchPrompt)
        .onSubmit(of: .search) { Task { await load() } }
        .onChange(of: query) { _, text in
            // Clearing the search (its ✕ or Cancel) shows everything again, as Pebble's "Clear search" does.
            if text.isEmpty && !searched.isEmpty { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            AppCopy.Memories.forgetTitle(forgetting.map { words($0) } ?? ""), isPresented: $isConfirmingForget,
            titleVisibility: .visible, presenting: forgetting
        ) { record in
            Button(AppCopy.Memories.forget, role: .destructive) { forget(record) }
            Button(AppCopy.Memories.keep, role: .cancel) {}
        } message: { _ in
            Text(AppCopy.Memories.forgetNote)
        }
        .toolbar {
            if let layer, canAdd {
                ToolbarItem(placement: .primaryAction) {
                    Button(AppCopy.Learning.addLayer(layer.name), systemImage: "plus") { isAdding = true }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            if let layer {
                AddMemorySheet(layer: layer) { Task { await load() } }
                    .lockCover()
            }
        }
        .navigationTitle(layer?.name ?? AppCopy.PebbleSettings.layer(layerID))
    }

    /// Pebble takes memories by hand in every layer but working context and past experiences.
    private var canAdd: Bool { store.bridgeOffers("memory_save") && MemoryLayers.takesMemoriesByHand(layerID) }

    private var layer: MemoryLayer? { store.memoryLayers.first { $0.id == layerID } }

    /// Pebble refuses to forget while a task runs; its button waits, and so does the phone's.
    private var canForget: Bool { store.bridgeOffers("memory_delete") && !store.isPebbleWorking }

    /// What the list shows: the working layer takes no search on the Mac's side, so its checkpoints are searched here
    /// by their words, as Pebble's window does.
    private var shown: [MemoryRecord] {
        guard layerID == "working", !searched.isEmpty else { return records }
        return records.filter { words($0).localizedCaseInsensitiveContains(searched) }
    }

    private func words(_ record: MemoryRecord) -> String {
        AppCopy.Memories.text(kind: record.kind, content: record.content, scope: record.scope)
    }

    private func chatTitle(_ id: ChatID?) -> String? {
        id.flatMap { id in store.chats.first { $0.id == id }?.title }
    }

    /// The first page, for the search typed (or everything).
    private func load() async {
        guard store.bridgeOffers("memory_list") else { return }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let page = await store.attempt({ try await store.memories(in: layerID, matching: search) }) else { return }
        records = page.records
        hasMore = page.hasMore
        searched = search
        isLoaded = true
    }

    private func loadMore() async {
        let shownCount = records.count
        guard let page = await store.attempt({ try await store.memories(in: layerID, matching: searched, after: shownCount) })
        else { return }
        records += page.records.filter { record in !records.contains { $0.id == record.id } }
        hasMore = page.hasMore
    }

    private func ask(_ record: MemoryRecord) {
        forgetting = record
        isConfirmingForget = true
    }

    private func forget(_ record: MemoryRecord) {
        Task {
            let forgot: Bool = await store.attempt { try await store.forget(record, words: words(record)) }
            if forgot {
                records.removeAll { $0.id == record.id }
                await load()
            }
        }
    }
}

import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// Pebble's Git decisions (`git_decisions`): which reviewed Git actions the person allows at all. Each still waits for
/// review every time. Sent back whole with the one switch changed.
struct GitDecisionsSection: View {
    let decisions: [String: JSONValue]
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Section {
            ForEach(shown, id: \.self) { key in
                RemoteToggle(
                    AppCopy.PebbleSettings.gitDecision(key),
                    subtitle: AppCopy.PebbleSettings.gitDecisionDetail(key),
                    value: decisions[key]?.bool ?? false, faceID: store.faceIDRule(forSetting: "git_decisions"),
                    marksFaceID: false
                ) { on in
                    await set(key, on)
                }
            }
        } header: {
            Text(AppCopy.PebbleSettings.gitDecisions)
        } footer: {
            // Face ID said once for the section (UX audit U-38).
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                if let note = store.faceIDNote(forSetting: "git_decisions") {
                    Text(note)
                }
                Text(AppCopy.PebbleSettings.gitDecisionsNote)
            }
        }
    }

    private var shown: [String] {
        let known = AppCopy.PebbleSettings.gitDecisionOrder.filter { decisions[$0] != nil }
        return known + decisions.keys.filter { !known.contains($0) }.sorted()
    }

    private func set(_ key: String, _ on: Bool) async -> Bool {
        var next = decisions
        next[key] = .bool(on)
        return await store.attempt { try await store.setGitDecisions(.object(next)) }
    }
}

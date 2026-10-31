import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's permission groups ("Available Tools"), each a switch, in Pebble's order. Every change goes through the
/// whole permissions object, so it asks for Face ID (an elevated call); Pebble applies it on the next task.
struct ToolSwitchesSection: View {
    let tools: [String: Bool]
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Section {
            ForEach(shown, id: \.self) { tool in
                RemoteToggle(
                    AppCopy.PebbleSettings.tool(tool), value: tools[tool] ?? false,
                    faceID: store.faceIDRule(forSetting: "permissions"), marksFaceID: false
                ) { on in
                    await store.attempt { try await store.setToolSwitch(tool, on: on) }
                }
            }
        } header: {
            Text(AppCopy.PebbleSettings.availableTools)
        } footer: {
            // Face ID said once for the section, not with a glyph on every switch (UX audit U-38).
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                if let note = store.faceIDNote(forSetting: "permissions") {
                    Text(note)
                }
                Text(AppCopy.PebbleSettings.toolsNote)
            }
        }
    }

    /// Pebble's order first, then any group a newer Pebble adds.
    private var shown: [String] {
        let known = AppCopy.PebbleSettings.toolOrder.filter { tools[$0] != nil }
        return known + tools.keys.filter { !known.contains($0) }.sorted()
    }
}

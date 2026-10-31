import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The Settings tab (once "Control"; UX audit U-35, docs/parity/IA.md rule 2): Pebble's Settings in its sidebar's order
/// and words, with the iPhone section where the Mac has its iPhone tab (between Privacy & Stealth and Appearance), then
/// the phone's lists across conversations. Your Mac (battery, Keep Awake, Mac Screen) is on the Pebble tab only (U-36).
/// The iPhone section shows even when Pebble isn't open, so the phone's own settings are always there. Each control
/// shows only when the bridge offers its method; changing the mode asks for Face ID, and Stop Everything asks for
/// confirmation.
struct ControlScreen: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Form {
            if store.usesUnlock && !store.isUnlocked {
                Section {
                    UnlockStatusRow()
                }
            }
            if let pebble = store.pebble {
                PebbleControlsSection(pebble: pebble, part: .beforeIPhone)
            }
            IPhoneSection()
            if let pebble = store.pebble {
                PebbleControlsSection(pebble: pebble, part: .afterIPhone)
            }
            MacListsSection()
        }
        // While the run accessory shows, rows that scroll under it are hidden behind a solid edge, as on Chats and
        // Reviews: "Toolbox" read through it (the re-check's U-04).
        .scrollEdgeEffectStyle(router.showsRunAccessory(in: store) ? .hard : nil, for: .bottom)
        .refreshable { await store.refresh() }
        .navigationTitle(AppCopy.Control.title)
    }
}

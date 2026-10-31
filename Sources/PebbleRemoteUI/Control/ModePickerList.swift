import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// "How Pebble acts": the three permission modes, each with its name and one line (UX audit U-07), and Pebble's exact
/// copy for every mode one tap away ("What Each Mode Allows"). Choosing one asks for Face ID (the store's elevated
/// call), said once under the modes (U-38); Pebble refuses while a task runs, and says so. Full access asks first, in two
/// sentences of Pebble's, with the risky button in red (U-50); while it is on, the whole warning stays under the modes,
/// as on the Mac (AdvancedSettings.vue).
struct ModePickerList: View {
    @Environment(RemoteStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var changingTo: PermissionMode?
    @State private var isConfirmingFullAccess = false

    var body: some View {
        Form {
            Section {
                ForEach(ModeCopy.order, id: \.self) { mode in
                    ModeRow(
                        mode: mode, isSelected: store.pebble?.mode == mode, isChanging: changingTo == mode,
                        needsFaceID: store.pebble?.mode != mode && store.settingNeedsProof("permissions")
                    ) {
                        request(mode)
                    }
                }
            } footer: {
                Text(AppCopy.Control.modeChangeNote)
            }
            if store.pebble?.mode == .full {
                Section {
                    // Full access reads in Pebble's danger colour (docs/DESIGN.md); system orange is 2.2:1 on white.
                    Label(AppCopy.Control.fullAccessWarning, systemImage: PebbleSymbol.status(.error))
                        .foregroundStyle(PebbleColor.danger)
                }
            }
            Section {
                DisclosureGroup(AppCopy.Modes.whatEachModeAllows) {
                    ForEach(ModeCopy.all) { copy in
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            Text(copy.name)
                                .font(.subheadline.weight(.semibold))
                            Text(AppCopy.Control.runsWithoutAskingLine(copy.mode))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(AppCopy.Control.alwaysAsksLine(copy.mode))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text(ModeCopy.everyMode)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let tools = store.settings?.tools, !tools.isEmpty {
                ToolSwitchesSection(tools: tools)
            }
            if let decisions = store.settings?.gitDecisions.object, !decisions.isEmpty {
                GitDecisionsSection(decisions: decisions)
            }
            // Lane S (SP-14): the Mac's "PEBBLE'S SHELL", one row; the list is read inside, after the unlock.
            if store.bridgeOffers("shell_grants") {
                Section(AppCopy.ShellAccess.section) {
                    NavigationLink(value: ControlRoute.shellGrants) {
                        Label(AppCopy.ShellAccess.row, systemImage: "apple.terminal")
                    }
                }
            }
        }
        .disabled(changingTo != nil || !store.bridgeOffers("setting"))
        .navigationTitle(AppCopy.Control.permissions)
        #if os(iOS)
        // A large title is cut at accessibility text sizes ("How Pebble…"; UX audit U-42); the inline one fits.
        .navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .automatic)
        #endif
        .alert(AppCopy.Modes.fullAccessTitle, isPresented: $isConfirmingFullAccess) {
            // The risky choice in the system's destructive red, never looking like Cancel (UX audit U-50).
            Button(AppCopy.Modes.fullAccessConfirm, role: .destructive) { choose(.full) }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppCopy.Modes.fullAccessMessage)
        }
    }

    /// Full access, the widest mode, asks first; the others go straight to Face ID.
    private func request(_ mode: PermissionMode) {
        guard mode != store.pebble?.mode, changingTo == nil else { return }
        if mode == .full {
            isConfirmingFullAccess = true
        } else {
            choose(mode)
        }
    }

    private func choose(_ mode: PermissionMode) {
        guard mode != store.pebble?.mode, changingTo == nil else { return }
        changingTo = mode
        Task {
            await store.attempt { try await store.setPermissionMode(mode) }
            changingTo = nil
        }
    }
}

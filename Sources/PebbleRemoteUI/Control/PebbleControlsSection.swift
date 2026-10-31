import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's Settings, as its Settings window on the Mac has them (UX audit U-35; docs/parity/IA.md rule 2): one section
/// per sidebar tab, in its order and with its names (AdvancedSettings.vue `TAB_LABELS`), each with what the phone can
/// change there. What only the Mac can do is an "On your Mac" row with the reason under it (IA rule 6). The iPhone
/// section sits between `beforeIPhone` (Models to Privacy & Stealth) and `afterIPhone` (Appearance, General), where
/// the Mac has its iPhone tab, and shows even without Pebble (`IPhoneSection`). The Mac lists Views only while its
/// window's Developer features switch is on, which the phone can't know, so the phone leaves Views out (the lead,
/// 23:03).
struct PebbleControlsSection: View {
    enum Part {
        /// Models, Permissions, Memory, Skills & connectors, Data & storage, Privacy & Stealth.
        case beforeIPhone
        /// Appearance, General.
        case afterIPhone
    }

    let pebble: PebbleOverview
    let part: Part
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @State private var isChangingStealth = false

    var body: some View {
        switch part {
        case .beforeIPhone: beforeIPhone
        case .afterIPhone: afterIPhone
        }
    }

    @ViewBuilder
    private var beforeIPhone: some View {
        models
        Section(AppCopy.SettingsTab.permissions) {
            NavigationLink(value: ControlRoute.mode) {
                LabeledContent(AppCopy.Control.permissions, value: ModeCopy.for(pebble.mode).name)
            }
        }
        if let settings = store.settings, store.bridgeOffers("setting") {
            Section(AppCopy.SettingsTab.memory) {
                NavigationLink(value: ControlRoute.memory) {
                    LabeledContent(
                        AppCopy.PebbleSettings.rememberContext,
                        value: settings.memoryEnabled ? AppCopy.PebbleSettings.on : AppCopy.PebbleSettings.off)
                }
            }
        }
        Section {
            if store.bridgeOffers("toolbox_list") {
                NavigationLink(value: ControlRoute.toolbox) {
                    Label(AppCopy.Control.toolbox, systemImage: "wrench.and.screwdriver")
                }
            }
            // Lane S (SK-04 to SK-09): the list and each one's Review, Enable and Disable; Remove and sign-in say "On
            // your Mac" inside. A bridge without `extensions` keeps the old row.
            if store.bridgeOffers("extensions") {
                NavigationLink(value: ControlRoute.extensions) {
                    Label(AppCopy.Skills.title, systemImage: "puzzlepiece.extension")
                }
            } else {
                OnYourMacRow(title: AppCopy.SettingsTab.skillsAndConnectors)
            }
        } header: {
            Text(AppCopy.SettingsTab.skills)
        } footer: {
            if !store.bridgeOffers("extensions") {
                Text(AppCopy.SettingsTab.skillsNote)
            }
        }
        storage
        if store.bridgeOffers("setting") || store.bridgeOffers("telemetry_get") {
            Section(AppCopy.SettingsTab.privacy) {
                if store.bridgeOffers("setting") {
                    // Pebble's own row: the Veil, the state line and the honest line (D47) under the switch, which
                    // moves only when Pebble confirms (design review A2).
                    StealthToggleRow(isOn: pebble.stealth, isBusy: isChangingStealth) { on in
                        guard !isChangingStealth else { return }
                        isChangingStealth = true
                        Task {
                            await store.attempt { try await store.setStealth(on) }
                            isChangingStealth = false
                        }
                    }
                }
                // Lane S (SS-03, SS-06): the Mac's "USAGE TELEMETRY". Whether it is on is read inside: the read needs
                // the unlock, which the Settings tab never asks for on its own.
                if store.bridgeOffers("telemetry_get") {
                    NavigationLink(value: ControlRoute.telemetry) {
                        Label(AppCopy.Telemetry.title, systemImage: "chart.bar.doc.horizontal")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var afterIPhone: some View {
        if let settings = store.settings, store.bridgeOffers("setting") {
            Section(AppCopy.SettingsTab.appearance) {
                NavigationLink(value: ControlRoute.macAppearance) {
                    LabeledContent(AppCopy.PebbleSettings.appearance, value: Self.themeName(settings.theme))
                }
            }
        }
        general
    }

    // MARK: - Models: the model, its effort and Fast Replies; connecting a model is the Mac's

    private var models: some View {
        Section {
            // The model by the name its list gives it ("GPT-5.1"), as the chip and the menus say it (UX audit U-26).
            if store.bridgeOffers("model_select") {
                NavigationLink(value: ControlRoute.models) {
                    LabeledContent(AppCopy.Control.model, value: store.currentModelName ?? AppCopy.Control.noModel)
                }
            } else if let model = store.currentModelName {
                LabeledContent(AppCopy.Control.model, value: model)
            }
            if let effort = pebble.effort {
                if store.bridgeOffers("model_effort") {
                    NavigationLink(value: ControlRoute.effort) {
                        LabeledContent(AppCopy.Control.effort, value: AppCopy.Control.effortName(effort))
                    }
                } else {
                    LabeledContent(AppCopy.Control.effort, value: AppCopy.Control.effortName(effort))
                }
            }
            if let fast = pebble.fastReplies, store.bridgeOffers("setting") {
                NavigationLink(value: ControlRoute.fastReplies) {
                    LabeledContent(AppCopy.Control.fastReplies, value: AppCopy.Control.fastRepliesName(fast))
                }
            }
            OnYourMacRow(title: AppCopy.SettingsTab.connectModel)
        } header: {
            Text(AppCopy.SettingsTab.models)
        } footer: {
            Text(AppCopy.SettingsTab.connectModelNote)
        }
        // The model list, read here so the Model row names the model as the list does.
        .task {
            if store.models.isEmpty, store.bridgeOffers("model_select") { await store.load(.models) }
        }
    }

    // MARK: - Data & storage: Recently Deleted is on Chats; Manage Data has the rest the phone can do

    private var storage: some View {
        Section {
            if store.bridgeOffers("storage_trash_chat") {
                // A shortcut that names where it leads (IA rule 4): Recently Deleted lives on the Chats tab.
                Button {
                    router.tab = .chats
                    // Over the Chats list itself, not over a conversation left open there.
                    router.chatsPath = []
                    router.isShowingRecentlyDeleted = true
                } label: {
                    LabeledContent {
                        Text(AppCopy.SettingsTab.inChats)
                    } label: {
                        Label(AppCopy.Deleted.title, systemImage: "trash")
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppCopy.SettingsTab.inChats)
            }
            // Lane S (SD-11, SD-12, SD-14, SD-15): the rest of the Mac's page, behind one row; what stays on the Mac
            // says so inside. A bridge without `storage_summary` keeps the old row.
            if store.bridgeOffers("storage_summary") {
                NavigationLink(value: ControlRoute.dataStorage) {
                    Label(AppCopy.DataStorage.manage, systemImage: "externaldrive")
                }
            } else {
                OnYourMacRow(title: AppCopy.SettingsTab.storageRow)
            }
        } header: {
            Text(AppCopy.SettingsTab.storage)
        } footer: {
            if !store.bridgeOffers("storage_summary") {
                Text(AppCopy.SettingsTab.storageNote)
            }
        }
    }

    // MARK: - General: the Mac's notifications, and which Pebble it is

    private var general: some View {
        Section(AppCopy.SettingsTab.general) {
            if store.bridgeOffers("setting") {
                NavigationLink(value: ControlRoute.notifications) {
                    Label(AppCopy.SettingsTab.notificationsOnYourMac, systemImage: "bell.badge")
                }
            }
            if !pebble.version.isEmpty {
                LabeledContent(AppCopy.SettingsTab.aboutPebble, value: pebble.version)
            }
        }
    }

    /// Pebble's theme by the name its Appearance settings give it.
    static func themeName(_ theme: String) -> String {
        switch theme {
        case "light": AppCopy.Settings.appearanceLight
        case "dark": AppCopy.Settings.appearanceDark
        default: AppCopy.Settings.appearanceSystem
        }
    }
}

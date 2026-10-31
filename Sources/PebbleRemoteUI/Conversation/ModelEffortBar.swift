import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The model and the effort Pebble uses, each a menu, as in the composer of Pebble's own window: chips above the
/// composer, or (`.menuItems`, at accessibility text sizes) two submenus inside the conversation's ⋯ menu. They are
/// Pebble's, for every conversation (`model_select`, `model_effort`). Each shows only what Pebble confirmed: a choice
/// sends the change, a spinner shows, and the name changes when Pebble's new state arrives. In a conversation, a new
/// model then offers "Continue with the new model" for a task there that can't resume on it (App.vue `changeModel`).
///
/// Pebble refuses changes while a task runs, so the choices wait until it ends, as on the Mac. The menus still open
/// then: they show the choices, greyed, under a header that says when they come back (the UX audit's U-09), rather than
/// a dimmed chip that does nothing when tapped.
struct ModelEffortBar: View {
    enum Style {
        /// Two glass chips in a row above the composer.
        case chips
        /// Two submenus, for a menu's content.
        case menuItems
    }

    /// The conversation the bar sits in; nil in a new conversation not made yet.
    var chatID: ChatID? = nil
    var style: Style = .chips
    @Environment(RemoteStore.self) private var store
    /// The menu whose change is on its way.
    @State private var changing: Part?

    private enum Part { case model, effort }

    var body: some View {
        if let pebble = store.pebble, offersModels || offersEffort {
            switch style {
            case .chips:
                GlassEffectContainer {
                    HStack(spacing: PebbleSpace.s2) {
                        if offersModels {
                            modelMenu
                        }
                        if offersEffort, !pebble.efforts.isEmpty {
                            effortMenu(pebble)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                // The glass style draws its label in the tint, over the label's own style: the app's sage failed
                // contrast on glass (the re-check: 37 and 34 flags), so the chips take the system's primary text.
                .tint(.primary)
                .disabled(changing != nil)
                .task {
                    if store.models.isEmpty { await store.load(.models) }
                }
            case .menuItems:
                if offersModels {
                    modelMenu
                }
                if offersEffort, pebble.efforts.count > 1 {
                    effortMenu(pebble)
                }
            }
        }
    }

    private var offersModels: Bool { store.bridgeOffers("model_select") }
    private var offersEffort: Bool { store.bridgeOffers("model_effort") }

    /// One model, one name: the name Pebble's model list gives it, as the menu shows it (U-26).
    private var modelName: String { store.currentModelName ?? AppCopy.Control.noModel }

    private var modelMenu: some View {
        Menu {
            waitsWhileWorking(AppCopy.Control.model) {
                Picker(AppCopy.Control.model, selection: choice(current: store.currentModelID ?? "", send: chooseModel)) {
                    ForEach(store.models) { model in
                        Text(model.name).tag(model.id)
                    }
                }
            }
        } label: {
            label(AppCopy.Control.model, value: modelName, isChanging: changing == .model)
        }
        .accessibilityLabel("\(AppCopy.Control.model), \(modelName)")
        .accessibilityHint(store.isPebbleWorking ? AppCopy.Control.modelWhileWorking : AppCopy.Control.modelForAllChats)
    }

    @ViewBuilder
    private func effortMenu(_ pebble: PebbleOverview) -> some View {
        let current = pebble.effort ?? pebble.defaultEffort ?? "default"
        let name = AppCopy.Control.effortName(current)
        if pebble.efforts.count > 1 {
            Menu {
                waitsWhileWorking(AppCopy.Control.effort) {
                    Picker(AppCopy.Control.effort, selection: choice(current: current, send: chooseEffort)) {
                        ForEach(pebble.efforts, id: \.self) { level in
                            if level == pebble.defaultEffort, level != "default" {
                                Text("\(AppCopy.Control.effortName(level)) · \(AppCopy.Control.recommended)").tag(level)
                            } else {
                                Text(AppCopy.Control.effortName(level)).tag(level)
                            }
                        }
                    }
                }
            } label: {
                label(AppCopy.Control.effort, value: name, isChanging: changing == .effort)
            }
            .accessibilityLabel("\(AppCopy.Control.effort), \(name)")
            .accessibilityHint(
                store.isPebbleWorking ? AppCopy.Control.modelWhileWorking : AppCopy.Control.effortForAllChats)
        } else {
            // A model without an effort control: its one level, never a menu.
            Text(name)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
                .padding(.horizontal, PebbleSpace.s2)
                .accessibilityLabel("\(AppCopy.Control.effort), \(name)")
                .accessibilityHint(AppCopy.Control.effortLocked)
        }
    }

    /// The choices under the menu's title; while Pebble works, greyed under a header that says when they come back
    /// instead. The menu keeps one shape either way, so Pebble starting or finishing a task (in any conversation) only
    /// changes words and greying in an open menu, rather than rebuilding it, which can close it (the re-check's U-53).
    private func waitsWhileWorking(_ title: String, @ViewBuilder _ choices: () -> some View) -> some View {
        let working = store.isPebbleWorking
        return Section(working ? AppCopy.AddContext.whileWorkingHint : title) {
            choices()
                .disabled(working)
        }
    }

    @ViewBuilder
    private func label(_ title: String, value: String, isChanging: Bool) -> some View {
        switch style {
        case .chips:
            HStack(spacing: PebbleSpace.s1) {
                Text(value)
                    .lineLimit(1)
                if isChanging {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }
            .font(PebbleFont.meta)
            // On the chip's glass: the system's primary text, not the sage tint, which failed the contrast audit.
            .foregroundStyle(.primary)
        case .menuItems:
            // A menu row: the control's name, with Pebble's current choice under it.
            Text(title)
            Text(value)
        }
    }

    /// The menu's selection reads Pebble's value; a pick only asks for the change.
    private func choice(current: String, send: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { current }, set: { wanted in if wanted != current { send(wanted) } })
    }

    private func chooseModel(_ id: String) {
        let chat = chatID
        change(.model) {
            if let chat {
                try await store.selectModel(id, from: chat)
            } else {
                try await store.selectModel(id)
            }
        }
    }

    private func chooseEffort(_ level: String) {
        change(.effort) { try await store.setEffort(level) }
    }

    private func change(_ part: Part, _ work: @escaping () async throws -> Void) {
        guard changing == nil else { return }
        changing = part
        Task {
            await store.attempt(work)
            changing = nil
        }
    }
}

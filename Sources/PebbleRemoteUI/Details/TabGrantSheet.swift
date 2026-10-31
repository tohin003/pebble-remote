import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A tab to grant: in the person's Chrome (only on the site they shared) or in Pebble's own browser.
struct TabGrantTarget: Identifiable, Hashable {
    var id: String { profile + "/" + tabID }
    let profile: String
    let tabID: String
    let title: String
    let origins: [String]

    var isChrome: Bool { profile == "chrome" }
}

/// "Let Pebble use this tab…" (PebbleBrowser.vue's grant card): the sites, what Pebble may do, screenshots for a Chrome
/// tab, and for how long; Grant this tab asks for Face ID. When Screen control is off, Pebble records nothing and says
/// so in its own words, with "Turn on Screen control and grant" when that can happen now.
struct TabGrantSheet: View {
    let target: TabGrantTarget
    let chatID: ChatID
    /// Pebble's notice once the tab is granted.
    let onGranted: (String) -> Void
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sites: Set<String>
    @State private var look = true
    @State private var fill = true
    @State private var press = false
    @State private var screenshots = false
    @State private var minutes = 15
    @State private var isGranting = false
    @State private var screenOff: (message: String, canTurnOn: Bool)?
    @State private var problem: String?

    init(target: TabGrantTarget, chatID: ChatID, onGranted: @escaping (String) -> Void) {
        self.target = target
        self.chatID = chatID
        self.onGranted = onGranted
        _sites = State(initialValue: Set(target.origins))
    }

    static let durations = [5, 15, 30]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: target.title.isEmpty ? AppCopy.Details.noTitle : target.title)
                        .font(PebbleFont.cardTitle)
                } footer: {
                    Text(
                        (target.isChrome
                            ? AppCopy.Details.grantChromeNote(target.origins.first ?? "") : AppCopy.Details.grantPebbleNote)
                            + " " + AppCopy.Details.grantWhen)
                }
                Section(AppCopy.Details.grantSites) {
                    ForEach(target.origins, id: \.self) { origin in
                        Toggle(origin, isOn: binding(for: origin))
                    }
                }
                Section(AppCopy.Details.grantWhat) {
                    Toggle(isOn: $look) { choice(AppCopy.Details.lookAround, AppCopy.Details.lookAroundNote) }
                    Toggle(isOn: $fill) { choice(AppCopy.Details.fillIn, AppCopy.Details.fillInNote) }
                    Toggle(isOn: $press) { choice(AppCopy.Details.pressButtons, AppCopy.Details.pressButtonsNote) }
                }
                if target.isChrome {
                    Section {
                        Toggle(AppCopy.Details.screenshotsToggle, isOn: $screenshots)
                    } header: {
                        Text(AppCopy.Details.screenshots)
                    } footer: {
                        Text(AppCopy.Details.screenshotsNote)
                    }
                }
                Section(AppCopy.Details.forHowLong) {
                    Picker(AppCopy.Details.forHowLong, selection: $minutes) {
                        ForEach(Self.durations, id: \.self) { count in
                            Text(AppCopy.Details.minutes(count)).tag(count)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if let screenOff {
                    Section {
                        Text(verbatim: screenOff.message)
                        Button(AppCopy.Details.turnOnScreenAndGrant, systemImage: PebbleSymbol.faceID) { grant(enableScreen: true) }
                            .disabled(!screenOff.canTurnOn || isGranting)
                    }
                }
                if let problem {
                    Section {
                        Label(problem, systemImage: PebbleSymbol.status(.error))
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
            }
            .navigationTitle(AppCopy.Details.grantTitle(chrome: target.isChrome))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel) { dismiss() }
                        .pebbleBarButton()
                }
                if screenOff == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppCopy.Details.grantThisTab) { grant(enableScreen: false) }
                            .pebbleBarButton()
                            .disabled(!canGrant || isGranting)
                    }
                }
            }
        }
        .formSheetDetents(typeSize)
    }

    private var actions: [String] {
        (look ? TabGrant.look : []) + (fill ? TabGrant.fill : []) + (press ? TabGrant.press : [])
    }

    private var canGrant: Bool { !sites.isEmpty && !actions.isEmpty }

    private func choice(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
            Text(title)
            Text(note)
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for origin: String) -> Binding<Bool> {
        Binding(
            get: { sites.contains(origin) },
            set: { on in
                if on { sites.insert(origin) } else { sites.remove(origin) }
            })
    }

    private func grant(enableScreen: Bool) {
        guard canGrant, !isGranting else { return }
        isGranting = true
        problem = nil
        let chosen = target.origins.filter(sites.contains)
        let grant = TabGrant(
            profile: target.profile, tabID: target.tabID, origins: chosen, actions: actions, minutes: minutes,
            screenshots: target.isChrome && screenshots)
        Task {
            do {
                switch try await store.grant(grant, in: chatID, enableScreen: enableScreen) {
                case .granted(let pending):
                    onGranted(
                        AppCopy.Details.granted(
                            chrome: target.isChrome, sites: chosen, pending: pending, minutes: minutes,
                            screenshots: grant.screenshots))
                    dismiss()
                case .needsScreenControl(let message, let canTurnOn):
                    screenOff = (message, canTurnOn)
                }
            } catch {
                problem = store.takeNotice()
            }
            isGranting = false
        }
    }
}

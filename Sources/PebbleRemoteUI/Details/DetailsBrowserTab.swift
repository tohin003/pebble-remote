import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Details › Browser (PebbleBrowser.vue, inventory item 13): Pebble for Chrome with Pause, Resume and Stop Pebble in
/// Chrome, the tabs the person shared and "Let Pebble use this tab…"; Pebble's own browser with Start (Face ID: it opens
/// on the Mac's screen) and Stop. Setting Chrome up, pairing and forgetting the browser's profile stay on the Mac: the
/// pairing code is shown there only, and the phone never reads it out.
struct DetailsBrowserTab: View {
    let state: DetailsState
    @Environment(RemoteStore.self) private var store
    @State private var busy = false
    @State private var done: String?
    @State private var isConfirmingStop = false
    @State private var granting: TabGrantTarget?

    var body: some View {
        List {
            if !store.readsQuietly {
                Section { UnlockStatusRow() }
            }
            if let done {
                Section {
                    Label(done, systemImage: "checkmark.circle")
                        .font(PebbleFont.cardBody)
                }
            }
            if let problem = state.browserProblem {
                Section {
                    Label(problem, systemImage: PebbleSymbol.status(.error))
                        .foregroundStyle(PebbleColor.danger)
                }
            }
            if store.bridgeOffers("browser_extension_status") {
                chromeSection
            }
            if store.bridgeOffers("browser_status") {
                pebbleBrowserSection
            }
            Section {
                OnYourMacRow(title: AppCopy.Details.chromeSetup)
                OnYourMacRow(title: AppCopy.Details.forgetProfile)
            } footer: {
                Text(AppCopy.Details.browserOnMacFootnote)
            }
        }
        .confirmationDialog(AppCopy.Details.stopInChrome, isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button(AppCopy.Details.stopInChrome, role: .destructive) { stopChrome() }
            Button(AppCopy.Common.cancel, role: .cancel) {}
        }
        .sheet(item: $granting) { target in
            TabGrantSheet(target: target, chatID: state.chatID) { words in
                done = words
                Task { await state.loadBrowser(store) }
            }
            .lockCover()
        }
        .task(id: store.readsQuietly) {
            if store.readsQuietly, state.chrome == nil, state.pebbleBrowser == nil { await state.loadBrowser(store) }
        }
        .refreshable {
            if store.readsQuietly { await state.loadBrowser(store) }
        }
    }

    // MARK: Your Chrome

    private var chromeSection: some View {
        Section {
            if let chrome = state.chrome {
                LabeledContent(
                    AppCopy.Details.yourChrome,
                    value: AppCopy.Details.chromeState(
                        connected: chrome.connected, paused: chrome.paused, pairing: chrome.pairing,
                        locked: chrome.pairingLocked, present: chrome.present, helper: chrome.helperInstalled))
                if chrome.connected, let version = chrome.chromeVersion {
                    Text(AppCopy.Details.chromeVersions(chrome: version, extension: chrome.extensionVersion))
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
                if chrome.paused {
                    Text(AppCopy.Details.chromePausedLine)
                        .font(PebbleFont.cardBody)
                }
                if chrome.pairing {
                    Text(AppCopy.Details.pairingOnMac)
                        .font(PebbleFont.cardBody)
                }
                if chrome.connected, chrome.sharedTabs.isEmpty {
                    Text(AppCopy.Details.noSharedTab)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(.secondary)
                }
                ForEach(chrome.sharedTabs) { tab in
                    sharedTabRow(tab)
                }
                if chrome.connected || !chrome.sharedTabs.isEmpty {
                    if store.bridgeOffers(chrome.paused ? "browser_extension_resume" : "browser_extension_pause") {
                        Button(
                            chrome.paused ? AppCopy.Details.resume : AppCopy.Details.pause,
                            systemImage: chrome.paused ? "play.circle" : "pause.circle", action: togglePause
                        )
                        .disabled(busy)
                    }
                    if store.bridgeOffers("browser_extension_stop") {
                        Button(AppCopy.Details.stopInChrome, systemImage: "stop.circle", role: .destructive) {
                            isConfirmingStop = true
                        }
                        .disabled(busy)
                    }
                }
            } else if store.readsQuietly {
                LabeledContent(AppCopy.Details.yourChrome, value: AppCopy.Details.chromeChecking)
            }
        } header: {
            Text(AppCopy.Details.yourChrome)
        } footer: {
            Text(AppCopy.Details.chromeNote)
        }
    }

    private func sharedTabRow(_ tab: ChromeStatus.SharedTab) -> some View {
        let session = liveSession(profile: "chrome", origin: tab.origin)
        return VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(AppCopy.Details.titleNote)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                Text(verbatim: tab.title.isEmpty ? AppCopy.Details.noTitle : tab.title)
                Text(
                    verbatim: [
                        AppCopy.Places.site(tab.origin), AppCopy.Details.tabScope(tab.scope),
                        AppCopy.Details.sharedTabState(tab.state, acting: tab.acting, granted: tab.granted),
                    ].joined(separator: " \u{00B7} ")
                )
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: PebbleSpace.s4) {
                if tab.state == "ready", store.bridgeOffers("screen_session_grant") {
                    Button(AppCopy.Details.letPebbleUseTab) {
                        granting = TabGrantTarget(profile: "chrome", tabID: tab.id, title: tab.title, origins: [tab.origin])
                    }
                }
                if let session, store.bridgeOffers("screen_session_revoke") {
                    Button(AppCopy.Details.endAccess, role: .destructive) { endAccess(session) }
                }
            }
            .buttonStyle(.borderless)
            .disabled(busy)
        }
    }

    // MARK: Pebble's browser

    private var pebbleBrowserSection: some View {
        Section {
            if let browser = state.pebbleBrowser {
                if browser.available || browser.running {
                    LabeledContent(
                        AppCopy.Details.pebbleBrowser,
                        value: AppCopy.Details.pebbleBrowserState(running: browser.running, product: browser.product))
                    if browser.running {
                        if store.bridgeOffers("browser_stop") {
                            Button(AppCopy.Details.stopBrowser, systemImage: "stop.circle", role: .destructive) { stopBrowser() }
                                .disabled(busy)
                        }
                        if state.pebbleTabs.isEmpty {
                            Text(AppCopy.Details.noTabs)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(state.pebbleTabs) { tab in
                            pebbleTabRow(tab)
                        }
                    } else if store.bridgeOffers("browser_start") {
                        Button(AppCopy.Details.startBrowser, systemImage: PebbleSymbol.faceID) { startBrowser() }
                            .disabled(busy)
                    }
                } else {
                    Text(browser.reason ?? AppCopy.Details.browserNotAvailable)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(.secondary)
                }
            }
            Button(AppCopy.Details.checkAgain, systemImage: "arrow.clockwise") {
                Task { await state.loadBrowser(store) }
            }
            .disabled(busy || !store.readsQuietly)
        } header: {
            Text(AppCopy.Details.pebbleBrowser)
        } footer: {
            Text(AppCopy.Details.pebbleBrowserNote)
        }
    }

    private func pebbleTabRow(_ tab: BrowserTab) -> some View {
        let session = tab.origin.flatMap { liveSession(profile: "pebble", origin: $0) }
        return VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(AppCopy.Details.titleNote)
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
                Text(verbatim: tab.title.isEmpty ? AppCopy.Details.noTitle : tab.title)
                Text(verbatim: AppCopy.Details.site(tab.origin))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: PebbleSpace.s4) {
                if let origin = tab.origin, store.bridgeOffers("screen_session_grant") {
                    Button(AppCopy.Details.letPebbleUseTab) {
                        granting = TabGrantTarget(profile: "pebble", tabID: tab.id, title: tab.title, origins: [origin])
                    }
                }
                if let session, store.bridgeOffers("screen_session_revoke") {
                    Button(AppCopy.Details.endAccess, role: .destructive) { endAccess(session) }
                }
            }
            .buttonStyle(.borderless)
            .disabled(busy)
        }
    }

    /// This conversation's live session on a tab of that browser and site (Pebble lists sessions by site, not tab).
    private func liveSession(profile: String, origin: String) -> ScreenSession? {
        store.screenSessions.first {
            $0.chatID == state.chatID && $0.kind == "browser" && $0.profile == profile && $0.origins.contains(origin)
        }
    }

    // MARK: Changing

    private func togglePause() {
        let pause = !(state.chrome?.paused ?? false)
        act(pause ? AppCopy.Details.pausedNotice : AppCopy.Details.resumedNotice) {
            _ = try await store.pauseChrome(pause)
        }
    }

    private func stopChrome() {
        guard !busy else { return }
        busy = true
        done = nil
        Task {
            if let tabs = await state.perform(store, { try await store.stopChrome() }) {
                done = AppCopy.Details.stoppedNotice(tabs)
            }
            await state.loadBrowser(store)
            busy = false
        }
    }

    private func startBrowser() {
        act(AppCopy.Details.browserStarted) { _ = try await store.startPebbleBrowser() }
    }

    private func stopBrowser() {
        act(AppCopy.Details.browserStopped) { try await store.stopPebbleBrowser() }
    }

    private func endAccess(_ session: ScreenSession) {
        act(AppCopy.Details.accessEnded(tab: true)) { try await store.revokeScreenSession(session) }
    }

    private func act(_ words: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        done = nil
        Task {
            if await state.perform(store, work) != nil { done = words }
            await state.loadBrowser(store)
            busy = false
        }
    }
}

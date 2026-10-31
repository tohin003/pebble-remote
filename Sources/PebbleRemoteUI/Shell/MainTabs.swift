import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The four tabs (iOS 26 `Tab`s; the bar stays whole, U-55) and, above the bar, the bottom accessory with the live run.
/// The Pebble tab's icon is Pebble itself (`PebbleGlyph`; the person, 2026-10-31: not a smiley): it blinks now and then,
/// wears Pebble's face for what Pebble is doing, and is happy for a moment when the tab is tapped, celebrating after
/// three quick taps, by the Mac companion's rules (only while Pebble rests, with the Mac's Reactions switch, never under
/// Reduce Motion). Pebble's reply banner shows at the top, in a space of its own: while it shows, the screen below it moves
/// down, so it never lies over a screen's title, its buttons or its first lines (the UX audit's U-21; floating over the
/// top, it covered other conversations' titles and Control's text in the re-check's 086, 097, 101 and 133). A haptic
/// says when something first needs the person.
struct MainTabs: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    /// The Pebble tab's glyph: a blink now and then, and the face a tap on the tab gives it for a moment.
    @State private var blinking = false
    @State private var tabReaction: PebbleAvatar.Pose?
    @State private var reactionEnds: Task<Void, Never>?
    @State private var tabTaps: [Date] = []
    /// Counts taps that changed the glyph's face, for the haptic; `celebrated` says which kind the last one was.
    @State private var reactionCount = 0
    @State private var celebrated = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: tabSelection) {
            Tab(value: AppTab.pebble) {
                OverviewTab()
                    .environment(\.appTab, .pebble)
            } label: {
                Label {
                    Text(AppCopy.Tabs.pebble)
                } icon: {
                    PebbleGlyph.image(pose: tabReaction ?? store.pebblePose, eyesClosed: blinking, scale: displayScale)
                }
            }
            Tab(AppCopy.Tabs.chats, systemImage: PebbleSymbol.tabChats, value: AppTab.chats) {
                ChatsTab()
                    .environment(\.appTab, .chats)
            }
            Tab(AppCopy.Tabs.reviews, systemImage: PebbleSymbol.tabReviews, value: AppTab.reviews) {
                ReviewsTab()
                    .environment(\.appTab, .reviews)
            }
            .badge(store.waiting.count)
            Tab(AppCopy.Tabs.control, systemImage: PebbleSymbol.tabControl, value: AppTab.control) {
                ControlTab()
                    .environment(\.appTab, .control)
            }
        }
        .modifier(TabShellChrome())
        .safeAreaInset(edge: .top, spacing: 0) {
            if let banner = store.banner, router.showsBanner(for: banner.chatID) {
                ReplyBannerView(banner: banner)
                    .padding(.bottom, PebbleSpace.s2)
                    .transition(PebbleMotion.transition(edge: .top, reduceMotion: reduceMotion))
            }
        }
        .pebbleAnimation(PebbleMotion.appear, value: store.banner)
        // A banner for the conversation on screen goes at once: its run's end line or card already says it there, and
        // the banner would only cover that conversation's title and menu (the UX audit's U-21).
        .onChange(of: store.banner, initial: true) { _, banner in
            if let banner, !router.showsBanner(for: banner.chatID) { store.dismissBanner() }
        }
        .sensoryFeedback(PebbleHaptics.needsYou, trigger: store.waiting.count) { old, new in old == 0 && new > 0 }
        .sensoryFeedback(trigger: reactionCount) { _, _ in
            celebrated ? SensoryFeedback.success : SensoryFeedback.impact(weight: .light, intensity: 0.7)
        }
        .task(id: reduceMotion) { await blinkNowAndThen() }
        .onChange(of: store.pebblePose) {
            // Pebble's own state wins at once: a run starting ends the glyph's reaction.
            if !Self.rests(store.pebblePose) { endReaction() }
        }
        .sheet(isPresented: $router.isChoosingMode) {
            ModePickerSheet()
                .lockCover()
        }
    }

    /// The tabs' selection, through which a tap on the Pebble tab, selected already or not, reaches its glyph.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { router.tab },
            set: { tab in
                if tab == .pebble { pebbleTabTapped() }
                router.tab = tab
            })
    }

    /// Pebble rests (nothing running, nothing waiting): only then does a tap change its face.
    private static func rests(_ pose: PebbleAvatar.Pose) -> Bool { pose == .idle || pose == .sleepy }

    /// A tap on the Pebble tab: happy for a moment, or a celebration after three quick taps (`PebbleTouchAvatar`'s
    /// timings). Never while Pebble works or waits for the person, nor with the Mac's Reactions off or under Reduce Motion.
    private func pebbleTabTapped() {
        guard Self.rests(store.pebblePose), store.companionSwitch("reactions"), !reduceMotion else { return }
        let now = Date.now
        tabTaps = tabTaps.filter { now.timeIntervalSince($0) < PebbleTouchAvatar.burstWindow } + [now]
        celebrated = tabTaps.count >= 3
        if celebrated { tabTaps = [] }
        reactionCount += 1
        tabReaction = celebrated ? .finished : .tap
        let hold = celebrated ? PebbleTouchAvatar.celebrationHold : PebbleTouchAvatar.tapHold
        reactionEnds?.cancel()
        reactionEnds = Task {
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            tabReaction = nil
        }
    }

    private func endReaction() {
        reactionEnds?.cancel()
        reactionEnds = nil
        tabReaction = nil
    }

    /// A blink every few seconds, as the avatar's own blinks come; none under Reduce Motion.
    private func blinkNowAndThen() async {
        blinking = false
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3.5...6.5)))
            guard !Task.isCancelled else { return }
            blinking = true
            try? await Task.sleep(for: .milliseconds(140))
            blinking = false
        }
    }
}

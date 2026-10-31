import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The overview's top: the avatar, what Pebble is doing now in its own words, and how the phone reaches the Mac. At
/// accessibility text sizes the avatar sits above the words, so they keep the row's full width. The avatar answers a
/// touch as the Mac's companion does (`PebbleTouchAvatar`), with the Mac's own Reactions and Follow the pointer
/// switches; the tab's own glyph in the tab bar is `MainTabs`'.
struct PebbleNowView: View {
    @Environment(RemoteStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize = 64

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PebbleSpace.s3))
            : AnyLayout(HStackLayout(spacing: PebbleSpace.s4))
        layout {
            PebbleTouchAvatar(
                pose: store.pebblePose, stealth: store.pebble?.stealth ?? false,
                reactions: store.companionSwitch("reactions"), followsFinger: store.companionSwitch("pointer")
            )
            .frame(width: avatarSize, height: avatarSize)
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                headlineText
                    .font(.title3)
                    .bold()
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                }
                ConnectionLine()
            }
        }
        .padding(.vertical, PebbleSpace.s2)
        .accessibilityElement(children: .combine)
    }

    private var pebbleRunning: Bool { store.isPebbleOpen }

    private var run: LiveRun? { store.liveRuns.first }

    /// What Pebble is doing. A live run's word counts on the shared clock, so it matches the run's Working Now pill and
    /// run bar at every moment (UX audit U-03); a waiting run keeps its one word. VoiceOver hears the key's sentence.
    @ViewBuilder
    private var headlineText: some View {
        if pebbleRunning, let run {
            TimelineView(.periodic(from: StatusCopy.rotationEpoch, by: 1)) { context in
                Text(
                    StatusCopy.word(
                        for: run.status, at: context.date, rotate: !reduceMotion, attempt: run.attempt)
                )
                .contentTransition(.opacity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(StatusCopy.label(for: run.status))
        } else {
            Text(pebbleRunning ? AppCopy.Home.idle : AppCopy.Home.pebbleNotOpen)
        }
    }

    private var detail: String? {
        if !pebbleRunning { return nil }
        if let run { return run.activity ?? run.chatTitle }
        return AppCopy.Home.idleDetail
    }
}

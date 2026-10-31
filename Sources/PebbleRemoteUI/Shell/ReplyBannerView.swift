import Accessibility
import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's banner for a conversation whose task ended or waits ("Pebble finished", "Pebble needs your review"; Pebble's
/// own words, D134), floating at the top for a few seconds. Tapping it opens the conversation. VoiceOver hears its
/// title as it appears: it usually leaves before VoiceOver would reach it.
struct ReplyBannerView: View {
    let banner: ReplyBanner
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(banner.title)
                    .font(.subheadline)
                    .bold()
                if !banner.body.isEmpty {
                    // On glass: Pebble's secondary text colour, which keeps 4.5:1, not the dimmed `.secondary`.
                    Text(banner.body)
                        .font(.footnote)
                        .foregroundStyle(PebbleColor.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, PebbleSpace.s4)
            .padding(.vertical, PebbleSpace.s3)
            .frame(minHeight: PebbleSize.minTap)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal)
        .task(id: banner.id) {
            if voiceOver { AccessibilityNotification.Announcement(banner.title).post() }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { store.dismissBanner() }
        }
    }

    private func open() {
        router.showChat(banner.chatID)
        store.dismissBanner()
    }
}

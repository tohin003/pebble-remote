import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Windows and browser tabs Pebble may use now, across conversations (Settings › Across Conversations). Each opens its
/// own conversation's Details on Tools, where Done and End access are: one home for each control (the lead's IA
/// decision, 2026-10-31 02:30), so nothing acts in place here.
struct ScreenSessionsView: View {
    @Environment(RemoteStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(store.screenSessions) { session in
                    let item = Self.item(session)
                    ToolsLinkRow(chatID: session.chatID) {
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            Label(item.title, systemImage: item.symbol ?? "macwindow")
                            Text(conversationTitle(session.chatID))
                                .font(PebbleFont.meta)
                                .foregroundStyle(.secondary)
                            if let detail = item.detail {
                                Text(detail)
                                    .font(PebbleFont.meta)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                if !store.screenSessions.isEmpty {
                    Text(AppCopy.Details.acrossListNote)
                }
            }
        }
        .overlay {
            if store.screenSessions.isEmpty {
                PebbleEmptyState(.noSharedWindows)
            }
        }
        .navigationTitle(AppCopy.Control.sharedWindows)
        .task { await store.load(.screenSessions) }
        .refreshable { await store.load(.screenSessions) }
    }

    /// The conversation a window belongs to, by its title as Chats lists it.
    private func conversationTitle(_ chat: ChatID) -> String {
        let title = store.chats.first { $0.id == chat }?.title ?? ""
        return title.isEmpty ? AppCopy.Chats.untitled : title
    }

    /// A tab by its site's name and its browser ("docs.github.com", "Your Chrome tab · Until 5:34 PM"); a window by its
    /// app's name as macOS shows it ("Mail"), never a raw address or a bundle ID (UX audit U-40, U-28).
    static func item(_ session: ScreenSession) -> ActionItem {
        let isTab = session.kind == "browser"
        let title =
            isTab
            ? AppCopy.Places.sites(session.origins) ?? AppCopy.Places.chromeTab
            : AppCopy.Places.appName(bundleID: session.bundleID) ?? AppCopy.Places.appWindow
        let until = session.expires.map { AppCopy.Sessions.until($0.formatted(date: .omitted, time: .shortened)) }
        let browser = isTab ? Self.browser(session.profile) : nil
        let detail = [browser, until].compactMap { $0 }.joined(separator: " \u{00B7} ")
        return ActionItem(
            id: session.id,
            title: title,
            detail: detail.isEmpty ? nil : detail,
            symbol: isTab ? "globe" : "macwindow",
            actionTitle: AppCopy.Control.revoke,
            actionSymbol: "xmark.circle",
            isDestructive: true)
    }

    /// Which browser a shared tab is in: the person's Chrome, or Pebble's own.
    static func browser(_ profile: String?) -> String? {
        switch profile {
        case "chrome": AppCopy.Places.chromeTab
        case "pebble": AppCopy.Places.pebbleTab
        default: nil
        }
    }

}

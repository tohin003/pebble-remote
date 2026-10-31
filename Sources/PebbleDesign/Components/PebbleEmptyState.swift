import SwiftUI

/// Empty and unavailable states, over Apple's `ContentUnavailableView`, with the pebble instead of a generic symbol
/// where Pebble itself is the subject. Titles are title style; the description says what will appear and how.
/// For search results use `ContentUnavailableView.search` directly.
///
/// ```swift
/// PebbleEmptyState(.noReviews)
/// PebbleEmptyState(.notConnected) { Button(AppCopy.Connection.tryAgain, action: retry) }
/// ```
public struct PebbleEmptyState<Actions: View>: View {
    public enum Kind: Sendable, Hashable, CaseIterable {
        case noChats, noReviews, notPaired, notConnected, pebbleClosed, nothingRunning, noSharedWindows, noTools,
            noSchedules
    }

    let kind: Kind
    let actions: Actions

    public init(_ kind: Kind, @ViewBuilder actions: () -> Actions) {
        self.kind = kind
        self.actions = actions()
    }

    public var body: some View {
        ContentUnavailableView {
            Label {
                Text(title)
            } icon: {
                if let pose {
                    PebbleAvatar(pose: pose, animated: false)
                        .frame(width: PebbleSize.avatarEmpty, height: PebbleSize.avatarEmpty)
                } else {
                    Image(systemName: symbol)
                }
            }
        } description: {
            Text(description)
        } actions: {
            actions
        }
    }

    /// The pebble's pose, when the pebble is the right picture for this state.
    private var pose: PebbleAvatar.Pose? {
        switch kind {
        case .noChats, .nothingRunning: .idle
        case .noReviews: .finished
        case .notPaired: .notify
        case .notConnected: .offline
        case .pebbleClosed: .sleepy
        case .noSharedWindows, .noTools, .noSchedules: nil
        }
    }

    private var symbol: String {
        switch kind {
        case .noSharedWindows: PebbleSymbol.screenSessions
        case .noTools: PebbleSymbol.toolbox
        case .noSchedules: PebbleSymbol.schedules
        default: PebbleSymbol.tabPebble
        }
    }

    private var title: String {
        switch kind {
        case .noChats: AppCopy.Empty.noChatsTitle
        case .noReviews: AppCopy.Empty.noReviewsTitle
        case .notPaired: AppCopy.Empty.notPairedTitle
        case .notConnected: AppCopy.Empty.notConnectedTitle
        case .pebbleClosed: AppCopy.Empty.pebbleClosedTitle
        case .nothingRunning: AppCopy.Empty.nothingRunningTitle
        case .noSharedWindows: AppCopy.Empty.noSharedWindowsTitle
        case .noTools: AppCopy.Empty.noToolsTitle
        case .noSchedules: AppCopy.Empty.noSchedulesTitle
        }
    }

    private var description: String {
        switch kind {
        case .noChats: AppCopy.Empty.noChatsDescription
        case .noReviews: AppCopy.Empty.noReviewsDescription
        case .notPaired: AppCopy.Empty.notPairedDescription
        case .notConnected: AppCopy.Empty.notConnectedDescription
        case .pebbleClosed: AppCopy.Empty.pebbleClosedDescription
        case .nothingRunning: AppCopy.Empty.nothingRunningDescription
        case .noSharedWindows: AppCopy.Empty.noSharedWindowsDescription
        case .noTools: AppCopy.Empty.noToolsDescription
        case .noSchedules: AppCopy.Empty.noSchedulesDescription
        }
    }
}

extension PebbleEmptyState where Actions == EmptyView {
    public init(_ kind: Kind) {
        self.init(kind) { EmptyView() }
    }
}

#if os(iOS)
#Preview("Empty states") {
    TabView {
        Tab(AppCopy.Tabs.reviews, systemImage: PebbleSymbol.tabReviews) { PebbleEmptyState(.noReviews) }
        Tab(AppCopy.Tabs.chats, systemImage: PebbleSymbol.tabChats) { PebbleEmptyState(.noChats) }
        Tab(StatusCopy.word(for: .offline), systemImage: PebbleSymbol.routeNone) {
            PebbleEmptyState(.notConnected) { Button(AppCopy.Connection.tryAgain) {} }
        }
    }
}
#endif

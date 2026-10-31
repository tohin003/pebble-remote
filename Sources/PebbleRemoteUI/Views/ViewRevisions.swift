import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// Lane T: a view's saved revisions on its screen (ArtifactPanel.vue `loadArtifact`, CV-02 and CV-08). The history
/// needs the unlock, so it is read when the screen opens only while quiet reads are allowed, and on the person's
/// Refresh. An earlier revision is shown read-only and never replaces the conversation's copy.
@MainActor
@Observable
final class ViewRevisions {
    /// Every saved revision, oldest first (empty until read).
    private(set) var history: [PebbleArtifact] = []
    /// The earlier revision on screen; nil while the current one shows.
    private(set) var earlier: PebbleArtifact?
    private(set) var isLoading = false

    /// The earlier revisions the person can choose, newest first ("Revision 2 · ready").
    func choices(below current: Int) -> [PebbleArtifact] {
        history.filter { $0.revision < current }.sorted { $0.revision > $1.revision }
    }

    /// Reads the history again; an earlier revision on screen is read again too. A failure is Pebble's words.
    func load(_ current: PebbleArtifact, store: RemoteStore) async -> String? {
        guard store.bridgeOffers("artifact_history") else { return nil }
        isLoading = true
        defer { isLoading = false }
        guard let rows = await store.attempt({ try await store.viewHistory(current) }) else {
            return store.takeNotice()
        }
        history = rows
        if let shown = earlier {
            if shown.revision >= current.revision {
                earlier = nil
            } else if let fresh = await store.attempt({ try await store.readRevision(shown.revision, of: current) }) {
                earlier = fresh
            } else {
                return store.takeNotice()
            }
        }
        return nil
    }

    /// Shows an earlier revision, or the current one (nil).
    func show(_ revision: Int?, of current: PebbleArtifact, store: RemoteStore) async -> String? {
        guard let revision, revision < current.revision else {
            earlier = nil
            return nil
        }
        isLoading = true
        defer { isLoading = false }
        guard let found = await store.attempt({ try await store.readRevision(revision, of: current) }) else {
            return store.takeNotice()
        }
        earlier = found
        return nil
    }

    /// A newer current revision arrived: an earlier one on screen stays earlier, unless it is the new current one.
    func follow(_ current: PebbleArtifact) {
        if let shown = earlier, shown.revision >= current.revision { earlier = nil }
    }
}

/// An earlier revision's note (Pebble's words for its kind) and the way back to the current one.
struct EarlierRevisionNote: View {
    let kind: String
    let current: Int
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Label(AppCopy.ViewHistory.earlierNote(kind: kind), systemImage: "clock.arrow.circlepath")
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.secondaryText)
            Button(AppCopy.ViewHistory.current(current), action: back)
                .buttonStyle(.pebbleSecondary)
        }
        .padding(PebbleSpace.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PebbleColor.soft, in: .rect(cornerRadius: PebbleRadius.md))
    }
}

import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One live run on the overview: its status word, how long (Pebble's exact time, shown once), the chat, what it is
/// doing, and Stop. At accessibility text sizes the time goes under the word, so neither runs out of room.
///
/// Stop shows only where Pebble's Mac offers it (`RunControls`, lane V's rule for U-10): a run that waits for an
/// approval or an answer shows its status only, since its card or question is the decision.
struct LiveRunRow: View {
    let run: LiveRun
    @Environment(RemoteStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isStopping = false
    @State private var stops = 0

    var body: some View {
        let statusLine = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PebbleSpace.s1))
            : AnyLayout(HStackLayout())
        let offersStop = store.bridgeOffers("cancel") && RunControls.offersStop(run.state)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                statusLine {
                    // The time shows here only: passing `since:` to the pill as well printed it twice.
                    StatusPill(status: run.status, attempt: run.attempt)
                    if let started = run.started {
                        ElapsedText(since: started)
                            .font(PebbleFont.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(run.chatTitle)
                    .font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                if let activity = run.activity {
                    Text(activity)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            // The status, its time, the chat and the step read as one element, not an 18-pt pill of their own.
            .accessibilityElement(children: .combine)
            Spacer()
            if offersStop {
                Button(action: stop) {
                    Label(AppCopy.Conversation.stop, systemImage: "stop.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .tapTarget()
                }
                .buttonStyle(.borderless)
                .disabled(isStopping)
            }
        }
        .swipeActions(edge: .trailing) {
            if offersStop {
                // Red, as a destructive action; the app's sage tint would otherwise colour it (U-18).
                Button(AppCopy.Conversation.stop, systemImage: "stop.fill", role: .destructive, action: stop)
                    .tint(.red)
            }
        }
        .sensoryFeedback(PebbleHaptics.stopped, trigger: stops)
    }

    private func stop() {
        isStopping = true
        Task {
            if await store.attempt({ try await store.stop(chat: run.chatID) }) { stops += 1 }
            isStopping = false
        }
    }
}

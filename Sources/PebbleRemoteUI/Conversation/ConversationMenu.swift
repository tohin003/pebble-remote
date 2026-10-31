import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The conversation's "More" menu: Rename; Details (Pebble's details drawer, during a task and after it: U-22); Pause
/// or Resume while a run is live; Resume for a stopped, interrupted, failed or limit-reached task, as Pebble's Details ›
/// Activity offers it (after new limits when the task reached its limit). Each item shows only when the bridge offers its method. Stop is not here: the run bar
/// above the composer holds the screen's one Stop (design review A1). Pause stays here for a run that waits for the
/// person, as Pebble's Details › Activity offers it, though its run bar then shows the status only (`RunControls`).
/// At accessibility text sizes the model and effort move here from the chips above the composer: the screen decides
/// (`ModelEffortPlacement`), since a toolbar caps the text size of what it holds and the menu can't tell for itself.
struct ConversationMenu: View {
    let transcript: Transcript
    @Binding var isRenaming: Bool
    var showDetails: ((RunID) -> Void)? = nil
    var present: RecoveryPresenter? = nil
    /// Where the screen puts the model and effort; `.menu` puts them here.
    var modelEffort: ModelEffortPlacement = .chips
    @Environment(RemoteStore.self) private var store
    /// Counts pauses and resumes Pebble took, for the haptic.
    @State private var runChanges = 0

    var body: some View {
        Menu(AppCopy.Conversation.more, systemImage: "ellipsis") {
            if modelEffort.showsInMenu {
                Section {
                    ModelEffortBar(chatID: transcript.chatID, style: .menuItems)
                }
            }
            if store.bridgeOffers("chat_rename") {
                Button(AppCopy.Chats.rename, systemImage: "pencil") {
                    isRenaming = true
                }
            }
            // Pebble's Details drawer is always one tap away (U-22): during a task and after it ends.
            if let showDetails, let run = DetailsOpening.run(for: transcript) {
                Button(AppCopy.Details.title, systemImage: DetailsTab.activity.symbol) {
                    showDetails(run)
                }
            }
            if let run = transcript.run {
                if store.bridgeOffers("run_pause") {
                    Button(
                        run.state == .paused ? AppCopy.Conversation.resume : AppCopy.Conversation.pause,
                        systemImage: run.state == .paused ? "play" : "pause", action: togglePause)
                }
            } else if let task = transcript.task,
                TaskControls.menuResumes(task, hasRunBar: false, offers: store.bridgeOffers)
            {
                Button(
                    task.needsLimits ? RecoveryCopy.Task.resumeWithLimits : RecoveryCopy.Task.resume,
                    systemImage: "play"
                ) {
                    resume(task)
                }
            }
        }
        .labelStyle(.iconOnly)
        .sensoryFeedback(PebbleHaptics.stopped, trigger: runChanges)
        // The model list, read for the menu's Model submenu too (the chips' bar isn't there to read it).
        .task(id: modelEffort) {
            if modelEffort.showsInMenu, store.models.isEmpty, store.bridgeOffers("model_select") {
                await store.load(.models)
            }
        }
    }

    private func togglePause() {
        RunActions.togglePause(transcript, store: store) { runChanges += 1 }
    }

    /// Resume, or its limits first after "Reached this task's limit.".
    private func resume(_ task: TaskAttention) {
        if task.needsLimits, let present {
            present(.limits(task))
            return
        }
        Task {
            if await store.attempt({ try await store.resume(task) }) { runChanges += 1 }
        }
    }
}

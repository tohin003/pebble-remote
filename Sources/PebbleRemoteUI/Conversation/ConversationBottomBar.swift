import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Below the transcript: the live run's bar (status word, elapsed time, Pause or Resume, Stop), what waits to go with
/// the next message, the model and effort Pebble uses, and the composer with its "+" menu, as in the composer of
/// Pebble's own window.
///
/// A run that waits for the person's decision shows its status only: no Stop and no Pause (`RunControls`, as on the
/// Mac); its card or question above is the decision. At accessibility text sizes the bar keeps to what can't move
/// elsewhere: the run's status without its activity line (the transcript shows the steps), and no model and effort
/// chips: the screen moves them into the conversation's ⋯ menu (`modelEffort`, decided once for both).
///
/// "Jump to Latest" sits at the bar's top, at its trailing end, while the transcript says the person is reading above
/// its end: as part of the bar it never lies over the transcript's lines or a card's buttons (the re-check's U-49).
struct ConversationBottomBar: View {
    let transcript: Transcript
    @Binding var sheet: ConversationSheet?
    /// Where the screen puts the model and effort: the chips show here only with `.chips`.
    var modelEffort: ModelEffortPlacement = .chips
    var showsJump = false
    var onJump: () -> Void = {}
    /// Whether the composer has the keyboard; the screen owns it, so a tap on the transcript closes the keyboard.
    var isWriting: FocusState<Bool>.Binding
    let onSent: () -> Void
    @Environment(RemoteStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts stops, pauses and resumes Pebble took, for the haptic.
    @State private var runChanges = 0

    var body: some View {
        // While a "/" command is typed its list sits above the field: the chips and Jump to Latest step aside, so the
        // bar stays short and nothing floats over the transcript (the re-check's U-57).
        let typingCommand = SlashInput.parse(store.unsent[.chat(transcript.chatID)]) != nil
        VStack(spacing: 0) {
            if showsJump && !typingCommand {
                HStack {
                    Spacer(minLength: 0)
                    Button(AppCopy.Conversation.jumpToLatest, systemImage: "arrow.down", action: onJump)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.pebbleGlass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.bottom, PebbleSpace.s2)
                .transition(.opacity)
            }
            if let run = transcript.run {
                RunBar(
                    status: run.status, title: modelEffort.showsInMenu ? "" : run.activity ?? "",
                    startedAt: run.started, isPaused: run.state == .paused, attempt: run.attempt,
                    stealth: store.pebble?.stealth ?? false, onStop: stopControl(for: run),
                    onPauseToggle: pauseControl(for: run))
                .padding(.horizontal)
            }
            if store.usesUnlock && !store.isUnlocked {
                UnlockStatusRow()
                    .padding(.horizontal)
                    .padding(.top, PebbleSpace.s2)
            }
            if let waiting = store.attachments[transcript.chatID], !waiting.isEmpty {
                PendingAttachmentsBar(attachments: waiting, remove: remove)
                    .padding(.top, PebbleSpace.s2)
            }
            if modelEffort.showsChips && !typingCommand {
                ModelEffortBar(chatID: transcript.chatID)
                    .padding(.horizontal)
                    .padding(.top, PebbleSpace.s2)
            }
            Composer(
                chatID: transcript.chatID, place: .chat(transcript.chatID), isRunLive: transcript.sendsGuidance,
                isFocused: isWriting, send: send, onSent: onSent
            ) {
                let offers = ComposerAddMenu.Offers.offered(by: store)
                if !offers.isEmpty {
                    ComposerAddMenu(offers: offers, isWorking: transcript.sendsGuidance, sheet: $sheet, attach: attach)
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: showsJump)
        .sensoryFeedback(PebbleHaptics.stopped, trigger: runChanges)
        // The model menu's list, read here so it is there in the ⋯ menu as well as on the chip.
        .task {
            if store.models.isEmpty, store.bridgeOffers("model_select") { await store.load(.models) }
        }
    }

    /// Stop, except on a run that waits for the person's decision (`RunControls`).
    private func stopControl(for run: LiveRun) -> (() -> Void)? {
        guard RunControls.offersStop(run.state) else { return nil }
        return { stop() }
    }

    /// Pause and Resume show only when the bridge offers them, and never on a run that waits for the person.
    private func pauseControl(for run: LiveRun) -> (() -> Void)? {
        guard store.bridgeOffers("run_pause"), RunControls.offersPauseInBar(run.state) else { return nil }
        return { togglePause() }
    }

    /// Remove shows only when the bridge offers it.
    private var remove: ((AttachmentRef) -> Void)? {
        guard store.bridgeOffers("remove_source") else { return nil }
        let chat = transcript.chatID
        return { attachment in
            Task { await store.attempt { try await store.removeAttachment(attachment, from: chat) } }
        }
    }

    private func send(_ text: String) async -> Bool {
        let chat = transcript.chatID
        return await store.attempt { try await store.send(text, in: chat) }
    }

    private func attach(_ data: Data, _ name: String, _ preview: Data?) async -> Bool {
        let chat = transcript.chatID
        return await store.attempt { try await store.attach(data, name: name, to: chat) }
    }

    private func stop() {
        RunActions.stop(transcript.chatID, store: store) { runChanges += 1 }
    }

    private func togglePause() {
        RunActions.togglePause(transcript, store: store) { runChanges += 1 }
    }
}

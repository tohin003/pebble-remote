import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The transcript with the run bar and composer pinned below it (a safe-area bar, so the transcript scrolls under the
/// bar's edge effect); the chat's title above with where it is (Companion or its project) under it, whose menu starts a
/// new conversation there or connects a project; and a menu with Rename, what Pebble did and Pause (and the model and
/// effort at accessibility text sizes, where the tab bar also gives the conversation its room).
struct TranscriptScreen: View {
    let transcript: Transcript
    @State private var sentCount = 0
    /// "Jump to Latest": the transcript says when it shows; the bottom bar shows it and counts the taps.
    @State private var showsJump = false
    @State private var jumpCount = 0
    /// The composer has the keyboard. Owned here, so a tap on the transcript closes it, as a tap on the Pebble tab's list
    /// does (the person, 2026-10-31: in Chats the keyboard stayed up).
    @FocusState private var isWriting: Bool
    @State private var isRenaming = false
    @State private var details: RunDetailsRequest?
    @State private var sheet: ConversationSheet?
    /// A task's sheet: the uncertain outcomes, Resume's new limits, a card's details, a command's typing or output.
    @State private var recovery: RecoverySheet?
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.appTab) private var appTab
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Decided here, from the screen's own text size, for both the bottom bar and the ⋯ menu (U-52): the toolbar
        // caps the text size of what it holds, so the menu can't tell for itself.
        let modelEffort = ModelEffortPlacement(textSize: typeSize)
        TranscriptList(
            transcript: transcript, sentCount: sentCount, jumpCount: jumpCount, showsJump: $showsJump,
            showDetails: showDetails, present: present
        )
        .closesKeyboardOnTap($isWriting)
        // Lines that scroll under the bar are hidden behind a solid edge, so none reads through the message field's
        // glass (the re-check's U-57; the Pebble tab's U-48 and Chats' U-04 had the same fix).
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .safeAreaBar(edge: .bottom) {
            ConversationBottomBar(
                transcript: transcript, sheet: $sheet, modelEffort: modelEffort, showsJump: showsJump,
                onJump: { jumpCount += 1 }, isWriting: $isWriting, onSent: noteSent)
        }
        // Pebble's name for an untitled conversation, as the chat list shows it, rather than an empty bar.
        .navigationTitle(transcript.title.isEmpty ? AppCopy.Chats.untitled : transcript.title)
        .navigationSubtitle(transcript.project ?? AppCopy.Sidebar.companion)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // At accessibility text sizes the conversation keeps the screen: no tab bar under its composer (U-43).
        .toolbarVisibility(typeSize.isAccessibilitySize ? .hidden : .automatic, for: .tabBar)
        #endif
        .toolbarTitleMenu {
            ConversationPlaceMenu(transcript: transcript, sheet: $sheet)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ConversationMenu(
                    transcript: transcript, isRenaming: $isRenaming, showDetails: showDetails, present: present,
                    modelEffort: modelEffort)
            }
        }
        .modifier(RenameChatAlert(transcript: transcript, isPresented: $isRenaming))
        .pebbleStatusAnnouncements(status: transcript.run?.status, finished: replyFinished)
        // A reply that finishes while the person watches (not one that had finished before they opened it).
        .sensoryFeedback(PebbleHaptics.finished, trigger: replyFinished) { wasFinished, isFinished in
            !wasFinished && isFinished
        }
        .sheet(item: $details) { request in
            RunDetailsView(request: request)
                .lockCover()
        }
        .sheet(item: $sheet) { which in
            ConversationSheetView(which: which, transcript: transcript, sheet: $sheet)
                .lockCover()
        }
        .sheet(item: $recovery) { which in
            RecoverySheetView(which: which)
                .lockCover()
        }
        // The conversation's commands, read again on Pebble's events; once connected and unlocked, never asking
        // Face ID itself.
        .task(id: [store.bridge?.bridgeVersion ?? "", store.unlockedUntil?.description ?? ""]) {
            store.watchCommands(in: transcript.chatID)
        }
        // Settings › Across Conversations opened this conversation for its Details › Tools (lane Y): the sheet opens
        // once the conversation's push has settled, on the task Details would open on from the ⋯ menu.
        .onChange(of: router.detailsToOpen, initial: true) {
            guard let target = router.takeDetails(for: transcript.chatID, on: appTab) else { return }
            let run = DetailsOpening.run(for: transcript)
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                details = RunDetailsRequest(chatID: target.chatID, runID: run, tab: target.tab)
            }
        }
    }

    private var present: RecoveryPresenter {
        { recovery = $0 }
    }

    /// Run details open in a sheet, when the bridge offers Pebble's run activity.
    private var showDetails: ((RunID) -> Void)? {
        guard store.bridgeOffers("run_activity") else { return nil }
        let chat = transcript.chatID
        return { run in details = RunDetailsRequest(chatID: chat, runID: run) }
    }

    /// The newest run's end is a finished one, with no message after it: VoiceOver says "Reply finished" once. Cards
    /// Pebble acted on, the task's controls, the handoff offer and commands may follow the end line.
    private var replyFinished: Bool {
        for item in transcript.items.reversed() {
            switch item {
            case .runEnd(_, _, let state, _, _): return state == .completed
            case .action, .task, .handoff, .command: continue
            default: return false
            }
        }
        return false
    }

    private func noteSent() {
        sentCount += 1
    }
}

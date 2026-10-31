import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Details › Tools: this conversation's schedules and the windows and tabs it may use (CompanionWorkflows.vue and
/// ScreenSessions.vue), so ending access is one tap away where it was given. The rows and their actions are the same as
/// Settings › Across Conversations (one store, one list); the footer says where the other conversations' are.
struct ToolsTab: View {
    let state: DetailsState
    @Environment(RemoteStore.self) private var store
    @State private var working: String?
    @State private var resuming: ScheduleResumption?
    @State private var isConfirmingResume = false
    @State private var deleting: ScheduleItem?
    @State private var isConfirmingDelete = false
    @State private var done: String?

    var body: some View {
        let chat = state.chatID
        let notices = store.jobNotices.filter { $0.chatID == chat }
        let schedules = store.schedules.filter { $0.chatID == chat }
        let sessions = store.screenSessions.filter { $0.chatID == chat }
        List {
            if !store.readsQuietly {
                Section { UnlockStatusRow() }
            }
            if !notices.isEmpty {
                Section(AppCopy.Details.scheduleNotices) {
                    ForEach(notices) { JobNoticeRow(notice: $0) }
                }
            }
            Section {
                if schedules.isEmpty {
                    Text(AppCopy.Details.noSchedules)
                        .foregroundStyle(.secondary)
                }
                ForEach(schedules) { item in
                    ScheduleRow(item: item, isWorking: working == item.id)
                        .swipeActions(edge: .leading) {
                            if item.isPaused || item.needsReview {
                                Button(AppCopy.Control.resumeSchedule, systemImage: "play.fill") { review(item) }
                                    .tint(PebbleColor.accent)
                            } else {
                                Button(AppCopy.Control.pauseSchedule, systemImage: "pause.fill") { pause(item) }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(AppCopy.Deleted.delete, systemImage: "trash", role: .destructive) {
                                deleting = item
                                isConfirmingDelete = true
                            }
                        }
                }
            } header: {
                Text(AppCopy.Details.schedules)
            } footer: {
                Text(AppCopy.Details.schedulesNote)
            }
            Section {
                if sessions.isEmpty {
                    Text(AppCopy.Details.noWindows)
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    sessionRow(session)
                }
                if let done {
                    Text(done)
                        .font(PebbleFont.meta)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(AppCopy.Control.sharedWindows)
            } footer: {
                Text(AppCopy.Details.windowsNote + " " + AppCopy.Details.toolsAlsoInSettings)
            }
        }
        .confirmationDialog(
            resuming.map { AppCopy.Schedules.resumeTitle($0.item.name) } ?? "", isPresented: $isConfirmingResume,
            titleVisibility: .visible, presenting: resuming
        ) { resumption in
            Button(AppCopy.Control.resumeSchedule) { resume(resumption) }
        } message: { resumption in
            Text(
                AppCopy.Schedules.resumeMessage(
                    mode: resumption.review.mode, modelName: resumption.review.modelName,
                    nextRun: resumption.review.nextTimes.first))
        }
        .confirmationDialog(
            deleting.map { AppCopy.Schedules.deleteTitle($0.name) } ?? "", isPresented: $isConfirmingDelete,
            titleVisibility: .visible, presenting: deleting
        ) { item in
            Button(AppCopy.Deleted.delete, role: .destructive) { run(item.id) { try await store.deleteSchedule(item) } }
        }
        .task(id: store.readsQuietly) {
            if store.readsQuietly { await store.loadTools(in: chat) }
        }
        .refreshable {
            if store.readsQuietly { await store.loadTools(in: chat) }
        }
    }

    /// A shared window or tab: what it is, its state and time left, with Done (when it's the person's turn or paused)
    /// and End access.
    private func sessionRow(_ session: ScreenSession) -> some View {
        let item = ScreenSessionsView.item(session)
        let isTab = session.kind == "browser"
        return VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Label(item.title, systemImage: item.symbol ?? "macwindow")
                Text(
                    [AppCopy.Details.sessionState(session.state, pending: session.pending), item.detail]
                        .compactMap { $0 }.joined(separator: " \u{00B7} ")
                )
                .font(PebbleFont.meta)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: PebbleSpace.s4) {
                if session.state != "active", store.bridgeOffers("screen_handoff_done") {
                    Button(AppCopy.Details.sessionDone) {
                        run(session.id, done: AppCopy.Details.sessionDoneNotice(tab: isTab)) {
                            try await store.markScreenSessionDone(session)
                        }
                    }
                    .buttonStyle(.borderless)
                }
                if store.bridgeOffers("screen_session_revoke") {
                    Button(AppCopy.Details.endAccess, role: .destructive) {
                        run(session.id, done: AppCopy.Details.accessEnded(tab: isTab)) {
                            try await store.revokeScreenSession(session)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
            .disabled(working != nil)
        }
    }

    private func pause(_ item: ScheduleItem) {
        run(item.id) { try await store.pauseSchedule(item) }
    }

    /// Asks Pebble what resuming would run with, then shows it for the person to confirm (then Face ID).
    private func review(_ item: ScheduleItem) {
        guard working == nil else { return }
        working = item.id
        Task {
            if let review = await state.perform(store, { try await store.reviewResume(item) }) {
                resuming = ScheduleResumption(item: item, review: review)
                isConfirmingResume = true
            }
            working = nil
        }
    }

    private func resume(_ resumption: ScheduleResumption) {
        run(resumption.item.id) { try await store.resumeSchedule(resumption.item, review: resumption.review) }
    }

    private func run(_ id: String, done words: String? = nil, _ work: @escaping () async throws -> Void) {
        guard working == nil else { return }
        working = id
        done = nil
        Task {
            if await state.perform(store, work) != nil { done = words }
            working = nil
        }
    }
}

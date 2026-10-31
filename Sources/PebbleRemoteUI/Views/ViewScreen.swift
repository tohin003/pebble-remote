import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// One of Pebble's views, full screen (IA: "an artifact card opens full screen"): its title, kind and version, then
/// the view drawn natively. It reads the view again when it opens and on pull to refresh (`artifact_get`, a read), and a
/// live dashboard can have Pebble read its panels again (`artifact_refresh`).
///
/// Lane T: the ⋯ menu holds the canvas's rarer controls, as Pebble's header and Details hold them: Refresh (the view
/// and its revisions, CV-02), Revision (an earlier one, read-only, CV-08), Export… (this view's export, CV-03) and Stop
/// view (CV-09, after the person confirms).
struct ViewScreen: View {
    @State private var artifact: PebbleArtifact
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var isRefreshing = false
    @State private var failure: String?
    @State private var isAnswering = false
    @State private var revisions = ViewRevisions()
    @State private var isExporting = false
    @State private var isConfirmingStop = false
    @State private var isStopping = false

    init(artifact: PebbleArtifact) {
        _artifact = State(initialValue: artifact)
    }

    /// The revision on screen: an earlier one the person chose, or the current one.
    private var shown: PebbleArtifact { revisions.earlier ?? artifact }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PebbleSpace.s4) {
                    ViewScreenHeader(artifact: shown, isEarlier: revisions.earlier != nil)
                    if let earlier = revisions.earlier {
                        EarlierRevisionNote(kind: earlier.kind, current: artifact.revision) { choose(nil) }
                    }
                    if revisions.earlier == nil || !Self.answersOnlyWhenCurrent(shown.kind) {
                        NativeViewBody(
                            artifact: shown,
                            canRefresh: revisions.earlier == nil && store.bridgeOffers("artifact_refresh"),
                            isRefreshing: isRefreshing, refresh: refreshData, answer: answer, feedback: feedback,
                            compose: composeQuizResult)
                    }
                    if let failure {
                        Text(verbatim: failure)
                            .font(PebbleFont.cardBody)
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
                .padding()
                .frame(maxWidth: PebbleSize.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(artifact.title ?? AppCopy.Views.kind(artifact.kind))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Views.close, action: close)
                }
                ToolbarItem(placement: .primaryAction) {
                    moreMenu
                }
            }
            .refreshable { await reread(withHistory: true) }
            .task { await reread(withHistory: store.readsQuietly) }
            .navigationDestination(isPresented: $isExporting) {
                ExportScreen(chatID: artifact.chatID, viewID: artifact.id)
            }
        }
        .sheet(isPresented: $isAnswering) {
            FormSheet(artifact: artifact)
                .lockCover()
        }
        .confirmationDialog(AppCopy.ViewHistory.stopTitle, isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button(AppCopy.ViewHistory.stop, role: .destructive, action: stop)
        } message: {
            Text(AppCopy.ViewHistory.stopMessage(waitingForm: artifact.waitsForAnswer))
        }
    }

    // MARK: The ⋯ menu

    private var moreMenu: some View {
        Menu {
            Button(AppCopy.Views.refresh, systemImage: "arrow.clockwise") {
                Task { await reread(withHistory: true) }
            }
            let earlier = revisions.choices(below: artifact.revision)
            if !earlier.isEmpty {
                Picker(selection: chosenRevision) {
                    Text(AppCopy.ViewHistory.current(artifact.revision)).tag(Int?.none)
                    ForEach(earlier, id: \.revision) { revision in
                        Text(AppCopy.ViewHistory.earlier(revision.revision, status: revision.status?.rawValue))
                            .tag(Int?.some(revision.revision))
                    }
                } label: {
                    Label(AppCopy.ViewHistory.revision, systemImage: "clock.arrow.circlepath")
                }
                .pickerStyle(.menu)
            }
            if artifact.isExportable, store.bridgeOffers("export_preview") {
                Button(AppCopy.ViewHistory.export, systemImage: "doc.text") { isExporting = true }
            }
            if canStop {
                Button(AppCopy.ViewHistory.stop, systemImage: "stop.circle", role: .destructive) {
                    isConfirmingStop = true
                }
            }
        } label: {
            Label(AppCopy.ViewHistory.more, systemImage: "ellipsis.circle")
        }
        .disabled(isStopping)
    }

    /// Stop works on the current revision of a live view (ArtifactPanel.vue `stopArtifact`).
    private var canStop: Bool {
        artifact.isLive && revisions.earlier == nil && store.bridgeOffers("artifact_stop")
    }

    private var chosenRevision: Binding<Int?> {
        Binding(get: { revisions.earlier?.revision }, set: { choose($0) })
    }

    /// Forms and quizzes take answers only in their current revision; an earlier one shows Pebble's note instead.
    static func answersOnlyWhenCurrent(_ kind: String) -> Bool { kind == "form" || kind == "quiz" }

    private func choose(_ revision: Int?) {
        let current = artifact
        Task { failure = await revisions.show(revision, of: current, store: store) }
    }

    // MARK: Actions

    private func close() {
        dismiss()
    }

    /// Send Feedback, where Pebble takes messages from this iPhone.
    private var feedback: ((String) -> Void)? {
        guard store.bridgeOffers("send"), revisions.earlier == nil else { return nil }
        return sendFeedback
    }

    /// An app demo's Send Feedback (App.vue `demoFeedback`): Pebble's words naming the revision and the screen go to the
    /// conversation's message box, and the view closes so the person can finish them and send.
    private func sendFeedback(_ screen: String) {
        router.write(AppCopy.Views.feedbackDraft(revision: artifact.revision, screen: screen), in: artifact.chatID)
        dismiss()
    }

    /// Lane Q: a quiz result shared after the run that made the quiz had finished. Pebble can't give it to that run, so
    /// it answers `compose` with words for the person to send (quiz_grading.py `share`), where Pebble's window only says
    /// "The app did not confirm the share.". On the phone the words go to the conversation's message box and the view
    /// closes, as Send Feedback does; sending stays the person's. Only where Pebble takes messages from this iPhone.
    private var composeQuizResult: ((String) -> Void)? {
        guard store.bridgeOffers("send") else { return nil }
        return writeQuizResult
    }

    private func writeQuizResult(_ words: String) {
        router.write(words, in: artifact.chatID)
        dismiss()
    }

    private func answer() {
        isAnswering = true
    }

    /// The view as Pebble keeps it now; quiet, so a failed read leaves the copy on screen. With `withHistory`, its
    /// revisions too (the person's Refresh, or on opening while quiet reads are allowed).
    private func reread(withHistory: Bool) async {
        if store.bridgeOffers("artifact_get"), let fresh = try? await store.readView(artifact.id, in: artifact.chatID),
            fresh != artifact
        {
            artifact = fresh
            revisions.follow(fresh)
        }
        if withHistory { failure = await revisions.load(artifact, store: store) }
    }

    private func refreshData() {
        guard !isRefreshing else { return }
        isRefreshing = true
        failure = nil
        let view = artifact
        Task {
            if let fresh = await store.attempt({ try await store.refreshDashboard(view) }) {
                artifact = fresh
            } else {
                failure = store.takeNotice()
            }
            isRefreshing = false
        }
    }

    /// Stop view, once the person confirmed: Pebble keeps the view as a new, stopped revision.
    private func stop() {
        guard !isStopping else { return }
        isStopping = true
        failure = nil
        let view = artifact
        Task {
            if let stopped = await store.attempt({ try await store.stopView(view) }) {
                artifact = stopped
                failure = await revisions.load(stopped, store: store)
            } else {
                failure = store.takeNotice()
            }
            isStopping = false
        }
    }
}

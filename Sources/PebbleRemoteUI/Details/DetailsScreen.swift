import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The conversation's Details: the phone's copy of Pebble's details drawer, one tap from the conversation's ⋯ menu
/// during and after a task (IA map; UX audit U-22). The drawer's tabs under Pebble's names in a segmented control
/// (a menu at accessibility text sizes), listed as Pebble lists them: a tab with something to show, or one the person
/// opened from "More sections"; a tab the bridge doesn't offer never shows. With nothing listed, Pebble's empty state.
struct DetailsScreen: View {
    let chatID: ChatID
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var state: DetailsState
    @State private var chosen: DetailsTab
    @State private var revealed: Set<DetailsTab> = []

    init(chatID: ChatID, runID: RunID?, tab: DetailsTab = .activity) {
        self.chatID = chatID
        _state = State(initialValue: DetailsState(chatID: chatID, runID: runID))
        _chosen = State(initialValue: tab)
        // A tab asked for from elsewhere (Settings opens Tools) stays listed, as one opened from More sections does.
        _revealed = State(initialValue: tab == .activity ? [] : [tab])
    }

    var body: some View {
        let transcript = store.transcript(for: chatID)
        let listing = DetailsListing(
            has: has(transcript), revealed: revealed, hasRun: state.runID != nil,
            offers: { tab in tab.methods.contains { store.bridgeOffers($0) } })
        let showing = listing.showing(chosen)
        NavigationStack {
            Group {
                if let showing {
                    content(showing, transcript: transcript)
                } else {
                    empty(listing)
                }
            }
            .safeAreaBar(edge: .top) {
                if listing.listed.count > 1 {
                    picker(listing)
                }
            }
            .navigationTitle(AppCopy.Details.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Common.done) { dismiss() }
                        .pebbleBarButton()
                }
                if showing != nil, !listing.more.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        moreMenu(listing)
                    }
                }
            }
        }
        .alert(state.notice ?? "", isPresented: $state.isShowingNotice) {}
        .onChange(of: listing.listed, initial: true) { _, listed in
            if !listed.contains(chosen), let first = listed.first { chosen = first }
        }
        .task(id: liveKey(transcript)) {
            await state.refresh(store, liveRun: transcript.run?.id, newest: DetailsOpening.run(for: transcript))
        }
    }

    @ViewBuilder
    private func content(_ tab: DetailsTab, transcript: Transcript) -> some View {
        switch tab {
        case .activity: ActivityTab(state: state)
        case .task: TaskTab(state: state, isWorking: transcript.run != nil)
        case .context: ContextTab(state: state)
        case .changes: ChangesTab(state: state, transcript: transcript)
        case .tools: ToolsTab(state: state)
        case .browser: DetailsBrowserTab(state: state)
        }
    }

    @ViewBuilder
    private func picker(_ listing: DetailsListing) -> some View {
        let picker = Picker(AppCopy.Details.sections, selection: $chosen) {
            ForEach(listing.listed) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .labelsHidden()
        if typeSize.isAccessibilitySize {
            picker
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        } else {
            picker
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, PebbleSpace.s2)
        }
    }

    /// "More sections" (DetailsDrawer.vue): the tabs with nothing yet, under the names Pebble's menu gives them.
    private func moreMenu(_ listing: DetailsListing) -> some View {
        Menu(AppCopy.Details.moreSections, systemImage: "ellipsis") {
            ForEach(listing.more) { tab in
                Button(tab.moreTitle, systemImage: tab.symbol) { open(tab) }
            }
        }
    }

    /// Pebble's empty state, with one button per tab that waits in "More sections" (App.vue `#empty`).
    private func empty(_ listing: DetailsListing) -> some View {
        ContentUnavailableView {
            Label(AppCopy.Details.emptyTitle, systemImage: DetailsTab.activity.symbol)
        } description: {
            Text(AppCopy.Details.emptyNote)
        } actions: {
            ForEach(listing.more) { tab in
                Button(tab.moreTitle) { open(tab) }
                    .buttonStyle(.pebbleSecondary)
            }
        }
    }

    private func open(_ tab: DetailsTab) {
        revealed.insert(tab)
        chosen = tab
    }

    /// What each tab has to show (App.vue `tabHasContent`): Activity and Context once the conversation has a task;
    /// Task with a current goal or helper agents; Changes in a project or after Pebble wrote files; Tools with a
    /// schedule, a schedule's notice or a shared window; Browser while a shared tab is live (Pebble lists it then too).
    private func has(_ transcript: Transcript) -> Set<DetailsTab> {
        var has: Set<DetailsTab> = []
        if state.runID != nil {
            has.formUnion([.activity, .context])
        }
        let delegated = state.steps?.details.items.contains { $0.kind == "child" } ?? false
        if state.goal != nil || !state.agents.isEmpty || delegated { has.insert(.task) }
        if transcript.workspace != nil || Self.wroteFiles(transcript) { has.insert(.changes) }
        let sessions = store.screenSessions.filter { $0.chatID == chatID }
        if !sessions.isEmpty || store.schedules.contains(where: { $0.chatID == chatID })
            || store.jobNotices.contains(where: { $0.chatID == chatID })
        {
            has.insert(.tools)
        }
        if sessions.contains(where: { $0.kind == "browser" }) { has.insert(.browser) }
        return has
    }

    static func wroteFiles(_ transcript: Transcript) -> Bool {
        transcript.items.contains { item in
            if case .action(let record) = item { record.kind == .edit && record.status == "applied" } else { false }
        }
    }

    /// Changes that should read the steps and lists again: the working task's progress, a task that needs the person,
    /// and the unlock (quiet reads wait for it).
    private func liveKey(_ transcript: Transcript) -> String {
        let run = transcript.run
        return [
            run?.id ?? "-", run?.state.rawValue ?? "-", run?.steps.map(String.init) ?? "-", run?.activity ?? "-",
            transcript.task?.id ?? "-", DetailsOpening.run(for: transcript) ?? "-", store.readsQuietly ? "quiet" : "locked",
        ].joined(separator: "|")
    }
}

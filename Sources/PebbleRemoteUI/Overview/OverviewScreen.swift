import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The overview's list: what Pebble is doing now, what waits for the person, the runs it works on, then your Mac.
/// Sections appear only when they have something to say. Ask Pebble sits in a bar pinned below the list, so its field
/// and its arrow stay above the keyboard while the person types (the UX audit's U-12), and the list's last rows scroll
/// clear of it.
///
/// Rows that scroll under the bar are hidden behind a solid edge rather than showing through it, where their words and
/// the field's ran into each other (the re-check's U-48), and the decisions come right after the hero, so they are
/// never the row under the bar.
///
/// The keyboard never traps the person here (their P1 of 2026-10-30: the tab has no Back, and the keyboard covers the tab
/// bar): a swipe down on the list closes it as in Messages, and so does a tap on the list while it is up; the tap is
/// simultaneous, so rows and buttons still take theirs, and it listens only while the field has the keyboard.
struct OverviewScreen: View {
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    /// Ask Pebble's field has the keyboard.
    @FocusState private var isAsking: Bool

    var body: some View {
        let working = WorkingNow.runs(store.liveRuns, waiting: store.waiting)
        List {
            Section {
                PebbleNowView()
            }
            if case .failed(let problem) = store.connection.phase {
                Section {
                    ConnectionProblemRow(problem: problem)
                }
            }
            if !store.waiting.isEmpty {
                Section(AppCopy.Home.needsYourReview) {
                    ReviewSummaryRow(waiting: store.waiting)
                }
            }
            if !working.isEmpty {
                Section(AppCopy.Home.workingNow) {
                    ForEach(working) { run in
                        NavigationLink(value: ChatRoute(chatID: run.chatID)) {
                            LiveRunRow(run: run)
                        }
                    }
                }
            }
            if let mac = store.mac {
                Section(AppCopy.Mac.title) {
                    MacSummaryRows(mac: mac)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollEdgeEffectStyle(.hard, for: .bottom)
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded { isAsking = false },
            including: isAsking ? .all : .subviews)
        .safeAreaBar(edge: .bottom) {
            if store.bridgeOffers("new_chat") {
                AskPebbleField(isFocused: $isAsking)
            }
        }
        .refreshable { await store.refresh() }
        .pebbleStatusAnnouncements(status: store.liveRuns.first?.status, finished: false)
        .navigationTitle(AppCopy.Home.title)
        .toolbar {
            if let mode = store.pebble?.mode {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        router.isChoosingMode = true
                    } label: {
                        ModeChip(mode: mode, onGlass: true)
                    }
                    .accessibilityLabel(AppCopy.Control.permissionsLabel(mode))
                }
            }
        }
    }
}

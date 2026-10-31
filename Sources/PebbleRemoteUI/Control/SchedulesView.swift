import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// Pebble's schedules across conversations (Settings › Across Conversations): the notices they left and each schedule,
/// each opening its own conversation's Details on Tools, where Pause, Resume, Delete and OK are. One home for each
/// control (the lead's IA decision, 2026-10-31 02:30): nothing acts in place here. New Schedule stays: it chooses its
/// conversation.
struct SchedulesView: View {
    @Environment(RemoteStore.self) private var store
    @State private var isCreating = false

    var body: some View {
        List {
            if !store.jobNotices.isEmpty {
                Section(AppCopy.Schedules.notices) {
                    ForEach(store.jobNotices) { notice in
                        ToolsLinkRow(chatID: notice.chatID) {
                            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                                Text(notice.title)
                                if let created = notice.created {
                                    Text(created.formatted(.relative(presentation: .named)))
                                        .font(PebbleFont.meta)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                ForEach(store.schedules) { item in
                    ToolsLinkRow(chatID: item.chatID) {
                        ScheduleRow(item: item, isWorking: false)
                    }
                }
            } footer: {
                if !store.schedules.isEmpty {
                    Text(AppCopy.Details.acrossListNote)
                }
            }
        }
        .overlay {
            if store.schedules.isEmpty && store.jobNotices.isEmpty {
                PebbleEmptyState(.noSchedules)
            }
        }
        .toolbar {
            if store.bridgeOffers("job_create") {
                ToolbarItem(placement: .primaryAction) {
                    Button(AppCopy.NewSchedule.add, systemImage: "plus") { isCreating = true }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            NewScheduleSheet()
                .lockCover()
        }
        .navigationTitle(AppCopy.Control.schedules)
        .task { await store.load(.schedules) }
        .refreshable { await store.load(.schedules) }
    }
}

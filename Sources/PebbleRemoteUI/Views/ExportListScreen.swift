import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// The conversation's earlier exports (`export_list`, the latest 50; Pebble's window lists them only for "/exports").
/// Read when this screen shows, never on a timer: each read is recorded on the Mac. Each opens its file's record.
struct ExportListScreen: View {
    let chatID: ChatID
    @Environment(RemoteStore.self) private var store
    @State private var records: [ExportResult]?
    @State private var failure: String?

    var body: some View {
        List {
            if let records {
                if records.isEmpty {
                    Text(AppCopy.Exports.noEarlierFiles)
                        .foregroundStyle(PebbleColor.secondaryText)
                }
                ForEach(records) { record in
                    NavigationLink {
                        ExportRecordScreen(chatID: chatID, record: record) { Task { await load() } }
                    } label: {
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            Text(verbatim: record.title ?? AppCopy.Exports.thisSource)
                            Text(
                                AppCopy.Exports.recordLine(
                                    format: record.format, status: record.status,
                                    created: record.created?.formatted(date: .abbreviated, time: .shortened))
                            )
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.secondaryText)
                        }
                    }
                }
            } else if let failure {
                Text(verbatim: failure)
                    .foregroundStyle(PebbleColor.danger)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(AppCopy.Exports.earlierFiles)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if let found = await store.attempt({ try await store.exports(in: chatID) }) {
            records = found
            failure = nil
        } else {
            failure = store.takeNotice()
        }
    }
}

/// One earlier export (`export_get`): Pebble's verdict and checks, the copies saved from the Mac, and Delete Pebble's
/// copy while Pebble still keeps the file.
struct ExportRecordScreen: View {
    let chatID: ChatID
    @State var record: ExportResult
    /// The list behind it reads again after a deletion.
    let changed: () -> Void
    @Environment(RemoteStore.self) private var store
    @State private var failure: String?
    @State private var done: String?
    @State private var isDeleting = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            ExportResultSections(result: record)
            if !record.saves.isEmpty {
                Section(AppCopy.Exports.saves) {
                    ForEach(record.saves) { save in
                        VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                            Text(verbatim: AppCopy.Exports.savedTo(save.path))
                                .textSelection(.enabled)
                            Text(AppCopy.Exports.savedCopy(verified: save.verified, sha256: save.sha256))
                                .font(PebbleFont.meta)
                                .foregroundStyle(PebbleColor.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if record.keepsFile {
                Section {
                    OnYourMacRow(title: AppCopy.Exports.saveOnMac(verified: record.status == "verified"))
                    if store.bridgeOffers("export_discard") {
                        Button(AppCopy.Exports.deleteCopy, role: .destructive) { isConfirmingDelete = true }
                            .disabled(isDeleting)
                    }
                } footer: {
                    Text(AppCopy.Exports.saveOnMacNote)
                }
            }
            if let done {
                Section { Label(done, systemImage: "checkmark.circle") }
            }
            if failure != nil {
                Section { SheetFailure(message: failure) }
            }
        }
        .navigationTitle(record.title ?? AppCopy.Exports.thisSource)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .confirmationDialog(AppCopy.Exports.deleteTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(AppCopy.Exports.deleteCopy, role: .destructive, action: delete)
        } message: {
            Text(AppCopy.Exports.deleteMessage)
        }
    }

    private func load() async {
        guard store.bridgeOffers("export_get") else { return }
        if let full = await store.attempt({ try await store.export(record.id, in: chatID) }) {
            record = full
        } else {
            failure = store.takeNotice()
        }
    }

    private func delete() {
        guard !isDeleting else { return }
        isDeleting = true
        failure = nil
        let id = record.id
        Task {
            if await store.attempt({ try await store.discardExport(id, in: chatID) }) {
                done = AppCopy.Exports.deleted
                changed()
                await load()
            } else {
                failure = store.takeNotice()
            }
            isDeleting = false
        }
    }
}

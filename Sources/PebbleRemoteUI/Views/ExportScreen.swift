import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// Export a view (Pebble's Details › Task "Export a view" with its ExportPanel.vue, DT-26 to DT-31; the canvas's
/// Export… opens it for one view). The view (when there are several), the format and, for a quiz, the answer key;
/// Preview export; Create file, with Cancel while Pebble makes it; then Pebble's readback verdict with its checks, and
/// Delete Pebble's copy. Save opens the Mac's Save dialog, so it is an "On your Mac" row; earlier files are one tap
/// away.
struct ExportScreen: View {
    let chatID: ChatID
    @Environment(RemoteStore.self) private var store
    @State private var chosenID: String?
    @State private var format = ExportFormat.html
    @State private var includeAnswers = false
    @State private var plan: ExportPlan?
    /// The view and options the plan pinned: a change drops the plan, as Pebble's panel does.
    @State private var pinned: Pin?
    @State private var result: ExportResult?
    @State private var status: String?
    @State private var busy: Busy?
    @State private var failure: String?
    @State private var isConfirmingDelete = false

    enum Busy { case preview, render, delete }

    struct Pin: Equatable {
        var viewID: String
        var revision: Int
        var format: ExportFormat
        var includeAnswers: Bool
    }

    init(chatID: ChatID, viewID: String?) {
        self.chatID = chatID
        _chosenID = State(initialValue: viewID)
    }

    private var views: [PebbleArtifact] { store.views(in: chatID).filter(\.isExportable) }

    /// The view chosen, else the newest (App.vue `exportTarget`).
    private var chosen: PebbleArtifact? { views.first { $0.id == chosenID } ?? views.last }

    var body: some View {
        Form {
            Section {
                if views.count > 1 {
                    Picker(AppCopy.Exports.view, selection: viewChoice) {
                        ForEach(views) { view in
                            Text(verbatim: view.title ?? AppCopy.Views.untitledView).tag(view.id)
                        }
                    }
                } else if let chosen {
                    LabeledContent(AppCopy.Exports.view, value: chosen.title ?? AppCopy.Views.untitledView)
                }
            } footer: {
                Text(AppCopy.Exports.note)
            }
            .disabled(busy != nil)
            Section(AppCopy.Exports.format) {
                Picker(AppCopy.Exports.format, selection: $format) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(AppCopy.Exports.formatName(format.rawValue)).tag(format)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if chosen?.kind == "quiz" {
                    Toggle(AppCopy.Exports.includeAnswers, isOn: $includeAnswers)
                }
            }
            .disabled(busy != nil)
            Section {
                Button(busy == .preview ? AppCopy.Exports.checking : AppCopy.Exports.preview, action: preview)
                    .disabled(busy != nil || chosen == nil)
            } footer: {
                if let status {
                    Text(status)
                }
            }
            if let plan {
                planSection(plan)
            }
            if let result {
                ExportResultSections(result: result)
                madeFileSection(result)
            }
            if failure != nil {
                Section { SheetFailure(message: failure) }
            }
            if store.bridgeOffers("export_list") {
                Section {
                    NavigationLink(AppCopy.Exports.earlierFiles) { ExportListScreen(chatID: chatID) }
                }
            }
        }
        .navigationTitle(AppCopy.Exports.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: currentPin) { _, now in dropPlan(ifNot: now) }
        .onChange(of: chosen?.id) { _, _ in result = nil }  // a verdict belongs to the view it was made from
        .confirmationDialog(AppCopy.Exports.deleteTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button(AppCopy.Exports.deleteCopy, role: .destructive, action: delete)
        } message: {
            Text(AppCopy.Exports.deleteMessage)
        }
    }

    // MARK: Sections

    private func planSection(_ plan: ExportPlan) -> some View {
        Section {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Text(verbatim: chosen?.title ?? AppCopy.Exports.thisSource)
                    .font(PebbleFont.cardTitle)
                Text(
                    AppCopy.Exports.planLine(
                        format: plan.format, revision: plan.revision, pages: plan.pages,
                        until: plan.deadline?.formatted(date: .omitted, time: .shortened))
                )
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
            }
            .accessibilityElement(children: .combine)
            if busy == .render {
                Label {
                    Text(AppCopy.Exports.creating)
                } icon: {
                    ProgressView()
                }
                Button(AppCopy.Exports.cancel, role: .cancel, action: cancelRender)
            } else {
                Button(AppCopy.Exports.createFile, action: render)
                    .disabled(busy != nil)
            }
        }
    }

    /// What can be done with the file Pebble keeps: Save is the Mac's (its Save dialog), Delete Pebble's copy asks
    /// first.
    @ViewBuilder
    private func madeFileSection(_ result: ExportResult) -> some View {
        if result.keepsFile {
            Section {
                OnYourMacRow(title: AppCopy.Exports.saveOnMac(verified: result.status == "verified"))
                if store.bridgeOffers("export_discard") {
                    Button(AppCopy.Exports.deleteCopy, role: .destructive) { isConfirmingDelete = true }
                        .disabled(busy != nil)
                }
            } footer: {
                Text(AppCopy.Exports.saveOnMacNote)
            }
        }
    }

    // MARK: Choices

    private var viewChoice: Binding<String> {
        Binding(get: { chosen?.id ?? "" }, set: { chosenID = $0 })
    }

    private var currentPin: Pin? {
        guard let chosen else { return nil }
        return Pin(viewID: chosen.id, revision: chosen.revision, format: format, includeAnswers: includeAnswers)
    }

    /// A plan pins one view, revision, format and option set; any change drops it (ExportPanel.vue's watchers).
    private func dropPlan(ifNot now: Pin?) {
        guard let pinned, pinned != now else { return }
        let previous = pinned
        self.pinned = nil
        if plan != nil, busy != .render {
            plan = nil
            if let now, now.viewID == previous.viewID, now.revision != previous.revision {
                status = AppCopy.Exports.viewChanged(now.revision)
            } else if now?.viewID == previous.viewID {
                status = AppCopy.Exports.optionsChanged
            } else {
                status = nil
            }
        }
    }

    // MARK: Calls

    private func preview() {
        guard busy == nil, let view = chosen, let pin = currentPin else { return }
        busy = .preview
        status = nil
        failure = nil
        let format = format
        let answers = includeAnswers
        Task {
            if let made = await store.attempt({
                try await store.previewExport(of: view, as: format, includeAnswers: answers)
            }) {
                plan = made
                pinned = pin
                status = AppCopy.Exports.previewReady
            } else {
                failure = store.takeNotice()
            }
            busy = nil
        }
    }

    private func render() {
        guard busy == nil, let reviewed = plan else { return }
        busy = .render
        status = AppCopy.Exports.creating
        failure = nil
        let chat = chatID
        Task {
            let made: ExportResult? = await store.attempt { try await store.renderExport(reviewed, in: chat) }
            plan = nil  // a plan is used once
            pinned = nil
            if let made {
                result = made
                status = AppCopy.Exports.verdictNote(made.status)
            } else {
                status = nil
                failure = store.takeNotice()
            }
            busy = nil
        }
    }

    private func cancelRender() {
        guard busy == .render, let reviewed = plan else { return }
        let chat = chatID
        Task {
            let asked: Bool = await store.attempt { _ = try await store.cancelExport(reviewed, in: chat) }
            if !asked { failure = store.takeNotice() }
        }
    }

    private func delete() {
        guard busy == nil, let made = result else { return }
        busy = .delete
        failure = nil
        let chat = chatID
        Task {
            if await store.attempt({ try await store.discardExport(made.id, in: chat) }) {
                result = nil
                status = AppCopy.Exports.deleted
            } else {
                failure = store.takeNotice()
            }
            busy = nil
        }
    }
}

/// Pebble's verdict on a file it made (ExportPanel.vue's result card): the verdict and its note, the reason, the file
/// line, each readback check, and Pebble's notes.
struct ExportResultSections: View {
    let result: ExportResult

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                Label(
                    AppCopy.Exports.verdict(result.status, format: result.format),
                    systemImage: result.status == "verified" ? "checkmark.seal" : "exclamationmark.triangle"
                )
                .font(PebbleFont.cardTitle)
                .foregroundStyle(result.status == "verified" ? PebbleColor.accent : PebbleColor.text)
                Text(AppCopy.Exports.verdictNote(result.status))
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
                if let reason = result.reason {
                    Text(verbatim: reason)
                        .font(PebbleFont.cardBody)
                }
                if let line = AppCopy.Exports.fileLine(
                    name: result.suggestedName, bytes: result.bytes, sheets: result.sheets, pages: result.pages,
                    coverage: result.coverage, revision: result.revision, sha256: result.sha256)
                {
                    Text(verbatim: line)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if !result.checks.isEmpty {
            Section(AppCopy.Exports.checks) {
                ForEach(result.checks) { check in
                    Label {
                        Text(
                            verbatim: AppCopy.Exports.check(
                                passed: check.passed, label: check.label, detail: check.detail)
                        )
                        .font(PebbleFont.cardBody)
                    } icon: {
                        Image(systemName: check.passed ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(check.passed ? PebbleColor.accent : PebbleColor.danger)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        if !result.notes.isEmpty {
            Section {
                ForEach(result.notes, id: \.self) { note in
                    Text(verbatim: note)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                }
            }
        }
    }
}

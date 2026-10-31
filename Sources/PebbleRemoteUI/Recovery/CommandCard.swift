import Accessibility
import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A command Pebble started that is running, or whose outcome Pebble couldn't confirm (ExecutionOutput.vue): its state
/// in a sentence ("A command is running"; Pebble's window says "Command: running"), and Pebble's controls for it: "Type
/// into the command" while it waits for typing, "Read output", "Record my inspection" for an uncertain outcome, "Stop
/// command" while it runs, and "Forget saved command output" once it settled. Pebble sends no command text here, only
/// its state.
struct CommandCard: View {
    let job: ProcessJob
    var present: RecoveryPresenter? = nil
    @Environment(RemoteStore.self) private var store
    @State private var terminal: ProcessTerminal?
    @State private var isBusy = false
    @State private var stops = 0

    var body: some View {
        let controls = CommandControls(
            job: job, offers: store.bridgeOffers, readsTerminals: store.readsTerminalsQuietly, terminal: terminal)
        PebbleCard(emphasis: job.needsInspection ? .pending : .plain) {
            // The state in words, never "Command: unknown" (UX audit U-33).
            Label(AppCopy.CommandState.title(job.state), systemImage: PebbleSymbol.card(.command))
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
            if job.state == "unknown" {
                Text(AppCopy.CommandState.lostTrack)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if job.outcomeUncertain && job.inspectionRecorded {
                Text(RecoveryCopy.Command.inspectionRecorded)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                if controls.typeInto {
                    Button(RecoveryCopy.Command.typeInto, systemImage: "keyboard") { present?(.typeInto(job)) }
                        .buttonStyle(.pebbleSecondary)
                }
                if controls.readOutput {
                    Button(RecoveryCopy.Command.readOutput, systemImage: "text.alignleft") { present?(.output(job)) }
                        .buttonStyle(.pebbleSecondary)
                }
                if controls.inspect {
                    Button(RecoveryCopy.Command.recordInspection, systemImage: "checklist") { present?(.inspect(job)) }
                        .buttonStyle(.pebbleSecondary)
                }
                if controls.stop {
                    Button(RecoveryCopy.Command.stop, systemImage: "stop.circle", action: stop)
                        .buttonStyle(.pebbleDestructive)
                        .accessibilityHint(RecoveryCopy.Command.stopHint)
                }
                if controls.forget {
                    Button(action: forget) {
                        Text(RecoveryCopy.Command.forgetOutput)
                            .tapTarget(alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .tint(PebbleColor.accent)
                }
            }
            .disabled(isBusy)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RecoveryCopy.Command.output)
        .sensoryFeedback(PebbleHaptics.stopped, trigger: stops)
        .task(id: "\(job.id)/\(job.state)") {
            terminal = job.isLive ? await store.readTerminal(of: job) : nil
        }
    }

    private func stop() {
        guard !isBusy else { return }
        isBusy = true
        let job = self.job
        Task {
            if await store.attempt({ try await store.stopCommand(job) }) { stops += 1 }
            isBusy = false
        }
    }

    private func forget() {
        guard !isBusy else { return }
        isBusy = true
        let job = self.job
        Task {
            await store.attempt { try await store.forgetOutput(of: job) }
            isBusy = false
        }
    }
}

/// Which of a command's controls show (ExecutionOutput.vue), given what the bridge offers.
struct CommandControls: Equatable {
    var typeInto = false
    var readOutput = false
    var inspect = false
    var stop = false
    var forget = false

    /// - Parameters:
    ///   - readsTerminals: the phone can read the command's terminal without Face ID; then "Type into the command" shows
    ///     only when it takes typing, as on the Mac. Otherwise it shows for a running command and the sheet checks.
    ///   - terminal: what the phone read of the terminal, if it could.
    init(job: ProcessJob, offers: (String) -> Bool, readsTerminals: Bool, terminal: ProcessTerminal?) {
        if job.isLive && offers("process_input_human") && offers("process_terminal") {
            typeInto = readsTerminals ? terminal?.takesTyping == true : true
        }
        readOutput = offers("process_read")
        inspect = job.needsInspection && offers("process_inspect")
        stop = job.isLive && offers("process_stop")
        forget = !job.isLive && job.canForgetOutput && offers("process_dismiss")
    }
}

/// "Type into the command": a line (sent with Enter), Ctrl-C or Ctrl-D. At a password prompt what the person types goes
/// to the command only; it is not shown, not stored, and the model cannot answer it. Above the field, the command's
/// latest lines (the end of what "Read output" shows), so the person sees what it asks before typing (UX audit U-32).
///
/// With the keyboard up only the sheet's bar and the field's row stay in view (UX audit U-51), so every control lives
/// there: the line goes with the keyboard's Send key or the bar's Send, Ctrl-C and Ctrl-D sit in a menu beside the
/// field, and "Sent." shows above the field. The command's lines take a few lines' height and scroll.
struct TypeIntoCommandSheet: View {
    let job: ProcessJob
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var terminal: ProcessTerminal?
    @State private var latest: String?
    @State private var line = ""
    @State private var isSending = false
    @State private var failure: String?
    @State private var sent = 0
    @FocusState private var isFocused: Bool
    /// One line of the command's output, at the person's text size.
    @ScaledMetric(relativeTo: .callout) private var outputLineHeight: CGFloat = 21

    /// ExecutionOutput's field takes 1,024 characters.
    private static let lineLimit = 1024
    /// How many of the command's last lines are read for above the field.
    static let shownLines = 6
    /// How many of them show without scrolling: the block never grows past this.
    static let visibleLines = 3
    /// At most this many pages of 4,000 characters are read to reach the end of the output.
    static let pagesRead = 8

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(AppCopy.CommandState.title(job.state))
                        .font(PebbleFont.cardTitle)
                }
                if let latest {
                    Section {
                        latestLines(latest)
                    } header: {
                        Text(AppCopy.CommandState.latestLines)
                    }
                }
                if let terminal {
                    if terminal.takesTyping {
                        if terminal.isSecret {
                            Section { Text(RecoveryCopy.Command.passwordPrompt) }
                        }
                        Section {
                            HStack(spacing: PebbleSpace.s2) {
                                field(secret: terminal.isSecret)
                                keysMenu
                            }
                        } header: {
                            // Above the field, so the keyboard never hides it: the line went (its words show in the
                            // command's lines above once the command echoes them).
                            HStack(alignment: .firstTextBaseline) {
                                Text(RecoveryCopy.Command.typeIntoField)
                                Spacer(minLength: PebbleSpace.s2)
                                if showsSent {
                                    Text(AppCopy.CommandState.sent)
                                        .foregroundStyle(PebbleColor.accent)
                                }
                            }
                            .textCase(nil)
                        }
                    } else {
                        Section { Text(RecoveryCopy.Command.takesNoTyping) }
                    }
                }
                if failure != nil {
                    Section { SheetFailure(message: failure) }
                }
            }
            // The keyboard always closes without sending: a scroll closes it, Done stays in the bar, and Send with
            // nothing typed drops the field's focus (`KeyboardRules`).
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if terminal == nil && failure == nil { ProgressView() }
            }
            .navigationTitle(RecoveryCopy.Command.typeInto)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.done) { dismiss() }
                        .pebbleBarButton()
                }
                if terminal?.takesTyping == true {
                    ToolbarItem(placement: .confirmationAction) {
                        // In the bar, so it stays above the keyboard; one word, so the title fits beside it.
                        Button(AppCopy.CommandState.send, action: sendLine)
                            .disabled(line.isEmpty || isSending)
                            .accessibilityLabel(RecoveryCopy.Command.sendLine)
                            .accessibilityIdentifier(RecoveryCopy.Command.sendLine)
                    }
                }
            }
            .sensoryFeedback(PebbleHaptics.sent, trigger: sent)
            .task { await load() }
        }
        .formSheetDetents(typeSize)
    }

    /// "Sent." once a line or a key went, until the person types again.
    private var showsSent: Bool { sent > 0 && line.isEmpty && !isSending }

    /// How many lines tall the block of the command's lines is: as many as it has, at most `visibleLines`.
    static func visibleLineCount(of text: String) -> Int {
        max(1, min(visibleLines, text.split(whereSeparator: \.isNewline).count))
    }

    /// The command's last lines in a block a few lines tall that scrolls, showing the newest first.
    private func latestLines(_ text: String) -> some View {
        let lines = Self.visibleLineCount(of: text)
        return ScrollView {
            Text(verbatim: text.isEmpty ? RecoveryCopy.Command.noOutputYet : text)
                .font(PebbleFont.code)
                .foregroundStyle(PebbleColor.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: CGFloat(lines) * outputLineHeight + PebbleSpace.s1)
    }

    /// The line to send; the keyboard's Send key sends it.
    @ViewBuilder
    private func field(secret: Bool) -> some View {
        Group {
            if secret {
                SecureField(RecoveryCopy.Command.typeIntoField, text: limited)
            } else {
                TextField(RecoveryCopy.Command.typeIntoField, text: limited)
            }
        }
        .font(.body.monospaced())
        .autocorrectionDisabled()
        #if os(iOS)
        .textInputAutocapitalization(.never)
        #endif
        .submitLabel(.send)
        .focused($isFocused)
        .onSubmit(sendLine)
    }

    /// Pebble's "Send Ctrl-C" and "Send Ctrl-D", beside the field, so they stay above the keyboard.
    private var keysMenu: some View {
        Menu {
            Button(RecoveryCopy.Command.ctrlC) { send(.ctrlC) }
            Button(RecoveryCopy.Command.ctrlD) { send(.ctrlD) }
        } label: {
            Label(AppCopy.CommandState.keys, systemImage: "control")
                .labelStyle(.iconOnly)
                .tapTarget()
        }
        .disabled(isSending)
        .accessibilityLabel(AppCopy.CommandState.keys)
    }

    private var limited: Binding<String> {
        Binding(get: { line }, set: { line = String($0.prefix(Self.lineLimit)) })
    }

    private func load() async {
        do {
            terminal = try await store.terminal(of: job)
            failure = nil
            if terminal?.takesTyping == true { isFocused = true }
        } catch {
            failure = store.takeNotice()
        }
        await readLatest()
    }

    /// The end of the command's saved output: pages are read from the start (Pebble's `process_read` has no "from the
    /// end"), up to `pagesRead` of them, and the last `shownLines` lines kept.
    private func readLatest() async {
        guard store.bridgeOffers("process_read") else { return }
        var after = 0
        var text = ""
        for _ in 0..<Self.pagesRead {
            guard let page = try? await store.readOutput(of: job, after: after) else {
                if latest == nil { failure = failure ?? store.takeNotice() }
                return
            }
            // Keep this page and the one before it, so a line split between pages stays whole.
            text = String(text.suffix(4_000)) + page.text
            guard page.more, page.next > after else { break }
            after = page.next
        }
        latest = Self.lastLines(of: text, count: Self.shownLines)
    }

    /// The last `count` lines of `text` that have something on them.
    static func lastLines(of text: String, count: Int) -> String {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        return lines.suffix(max(0, count)).joined(separator: "\n")
    }

    private func sendLine() {
        // Send or Return with nothing typed closes the keyboard instead (Pebble sends no empty line either).
        guard !line.isEmpty else {
            isFocused = false
            return
        }
        guard !isSending else { return }
        let words = line
        perform { try await store.typeLine(words, into: job) } then: { line = "" }
    }

    private func send(_ key: ProcessKey) {
        perform { try await store.sendKey(key, to: job) } then: {}
    }

    private func perform(_ work: @escaping () async throws -> Void, then done: @escaping () -> Void) {
        isSending = true
        failure = nil
        Task {
            if await store.attempt(work) {
                sent += 1
                done()
                AccessibilityNotification.Announcement(AppCopy.CommandState.sent).post()
                await load()
            } else {
                failure = store.takeNotice()
            }
            isSending = false
        }
    }
}

/// "Record my inspection": for a command whose outcome Pebble couldn't observe, what the person saw and a note.
/// Recording it lets Pebble go on with newly reviewed project actions; the command's effects stay unverified.
struct InspectCommandSheet: View {
    let job: ProcessJob
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var observation = ProcessObservation.stillUncertain
    @State private var note = ""
    @State private var isSending = false
    @State private var failure: String?
    @State private var asksForNote = false
    @FocusState private var isWritingNote: Bool

    /// ExecutionOutput's note takes 500 characters.
    private static let noteLimit = 500

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(AppCopy.CommandState.title(job.state))
                        .font(PebbleFont.cardTitle)
                    if job.state == "unknown" {
                        Text(AppCopy.CommandState.lostTrack)
                            .font(PebbleFont.cardBody)
                    }
                }
                Section {
                    Picker(RecoveryCopy.Command.observedOutcome, selection: $observation) {
                        ForEach(ProcessObservation.allCases, id: \.self) { value in
                            Text(RecoveryCopy.Command.observation(value.rawValue)).tag(value)
                        }
                    }
                }
                Section {
                    TextField(
                        RecoveryCopy.Command.inspectionNote,
                        text: Binding(
                            get: { note },
                            set: {
                                note = String($0.prefix(Self.noteLimit))
                                if !Self.isBlank(note) { asksForNote = false }
                            }),
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                    .focused($isWritingNote)
                    // Return in an empty note closes the keyboard (the person can always close it without sending).
                    .closesKeyboardOnEmptyReturn($note, focus: $isWritingNote)
                } header: {
                    Text(RecoveryCopy.Command.inspectionNote)
                        .textCase(nil)
                } footer: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        // Pebble records an inspection only with a note: say so, rather than a dimmed button.
                        if asksForNote {
                            Text(AppCopy.CommandState.noteNeeded)
                                .foregroundStyle(PebbleColor.danger)
                        }
                        Text(RecoveryCopy.Command.inspectionNoteHint)
                    }
                }
                if failure != nil {
                    Section { SheetFailure(message: failure) }
                }
            }
            // A scroll closes the keyboard; Cancel stays in the bar.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(RecoveryCopy.Command.recordInspection)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel) { dismiss() }
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Enabled once an outcome is chosen (one always is: "Still uncertain after inspection" first, as
                    // on the Mac); without a note it asks for one (UX audit U-44).
                    Button(RecoveryCopy.Command.recordInspection, action: record)
                        .disabled(isSending)
                }
            }
        }
    }

    static func isBlank(_ text: String) -> Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func record() {
        guard !isSending else { return }
        guard !Self.isBlank(note) else {
            asksForNote = true
            isWritingNote = true
            return
        }
        isSending = true
        failure = nil
        let chosen = observation, words = note
        Task {
            if await store.attempt({ try await store.recordInspection(of: job, chosen, note: words) }) {
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isSending = false
        }
    }
}

/// "Read output": a page of the command's saved output, as Pebble keeps it, then "Next output page". The output is the
/// command's own text, shown as it is; Pebble hides terminal control sequences and says how many.
struct CommandOutputSheet: View {
    let job: ProcessJob
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var output: ProcessOutput?
    @State private var isReading = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PebbleSpace.s3) {
                    Text(AppCopy.CommandState.title(output?.state ?? job.state))
                        .font(PebbleFont.cardTitle)
                    if let output {
                        if output.incomplete {
                            Text(RecoveryCopy.Command.partialOutput)
                                .font(PebbleFont.meta)
                                .foregroundStyle(.secondary)
                        }
                        if output.controlsRemoved > 0 {
                            Text(RecoveryCopy.Command.controlsHidden(output.controlsRemoved))
                                .font(PebbleFont.meta)
                                .foregroundStyle(.secondary)
                        }
                        Text(verbatim: output.text.isEmpty ? RecoveryCopy.Command.noOutputYet : output.text)
                            .font(PebbleFont.code)
                            .foregroundStyle(PebbleColor.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(PebbleSpace.s3)
                            .background(PebbleColor.code, in: PebbleShapes.inset)
                            .accessibilityLabel(RecoveryCopy.Command.output)
                            .accessibilityValue(output.text)
                    }
                    SheetFailure(message: failure)
                }
                .padding()
            }
            .overlay {
                if output == nil && failure == nil { ProgressView() }
            }
            .navigationTitle(RecoveryCopy.Command.readOutput)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppCopy.Common.done) { dismiss() }
                        .pebbleBarButton()
                }
                if output?.more == true {
                    ToolbarItem(placement: .primaryAction) {
                        Button(RecoveryCopy.Command.nextOutputPage) { Task { await read(after: output?.next ?? 0) } }
                            .disabled(isReading)
                    }
                }
            }
            .task { await read(after: 0) }
            .refreshable { await read(after: 0) }
        }
    }

    private func read(after: Int) async {
        guard !isReading else { return }
        isReading = true
        do {
            output = try await store.readOutput(of: job, after: after)
            failure = nil
        } catch {
            failure = store.takeNotice()
        }
        isReading = false
    }
}

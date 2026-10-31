import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Terminal command" (Pebble's dialog, "Run a terminal command"), in Pebble's words: one command in the conversation's
/// project, with or without network access. It goes to Pebble's review, which takes over: the command waits as Pebble's
/// card, and its output appears in the conversation. Without a project Pebble can't run it, so the sheet offers
/// "Connect a project" instead, as the Mac's dialog does.
struct TerminalCommandSheet: View {
    /// The project's folder name; nil when the conversation has none.
    let project: String?
    /// Sends the command (and whether it may use the network); returns whether Pebble took it.
    let propose: (String, Bool) async -> Bool
    let connectProject: () -> Void
    @Environment(RemoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var command = ""
    @State private var network = false
    @State private var isSending = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppCopy.TerminalCommand.placeholder, text: $command, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityLabel(AppCopy.TerminalCommand.field)
                        .focused($isFocused)
                        // Return with nothing typed closes the keyboard (the person can always close it).
                        .closesKeyboardOnEmptyReturn($command, focus: $isFocused)
                    Toggle(AppCopy.TerminalCommand.network, isOn: $network)
                } header: {
                    Text(AppCopy.TerminalCommand.intro(project))
                        .textCase(nil)
                } footer: {
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) {
                        Text(AppCopy.TerminalCommand.note)
                        if project != nil, store.isPebbleWorking {
                            Text(AppCopy.TerminalCommand.whileWorking)
                        }
                    }
                }
                if project == nil {
                    Section {
                        Button(AppCopy.Sidebar.connectProject, systemImage: "folder.badge.plus", action: connectProject)
                    } footer: {
                        Text(AppCopy.TerminalCommand.needsProject)
                    }
                }
                if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(PebbleColor.danger)
                    }
                }
            }
            // A scroll closes the keyboard; Cancel stays in the bar.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(AppCopy.TerminalCommand.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // Pebble's title in full: on two lines where one doesn't fit between Cancel and Review (UX audit
                    // U-27: "Run a terminal com…"). The bar keeps its own size, as the system's titles do.
                    Text(AppCopy.TerminalCommand.title)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppCopy.Common.cancel, role: .cancel, action: close)
                        .pebbleBarButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    // One word, so the title fits between the buttons (UX audit U-27); VoiceOver hears Pebble's words.
                    Button(AppCopy.SheetActions.review, action: review)
                        .disabled(!canReview)
                        .accessibilityLabel(AppCopy.TerminalCommand.review)
                        .accessibilityIdentifier(AppCopy.TerminalCommand.review)
                }
            }
            .onAppear { isFocused = project != nil }
        }
        .formSheetDetents(typeSize)
    }

    private var trimmed: String { command.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// As the Mac's "Review command": a project, no task running, and a command.
    private var canReview: Bool {
        project != nil && !store.isPebbleWorking && !trimmed.isEmpty && !isSending
    }

    private func close() {
        dismiss()
    }

    private func review() {
        guard canReview else { return }
        let words = trimmed
        let allowNetwork = network
        isSending = true
        failure = nil
        Task {
            if await propose(words, allowNetwork) {
                dismiss()
            } else {
                failure = store.takeNotice()
            }
            isSending = false
        }
    }
}

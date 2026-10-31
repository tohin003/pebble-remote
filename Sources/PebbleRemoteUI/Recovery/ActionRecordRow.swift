import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A card Pebble already acted on, with the Undo Pebble's window offers for it (App.vue's earlier actions): "Undo this
/// edit", "Undo this command", "Undo this change" (each puts files back, so each asks for Face ID), or "Propose undo
/// (new reviewed plan)" for a Git change. It sits at the end of the turn it happened in. After an Undo the card reads
/// "Undone", with Pebble's notice ("Edit undone", "Some changes could not be undone").
struct ActionRecordRow: View {
    let record: ActionRecord
    @Environment(RemoteStore.self) private var store
    @State private var isBusy = false
    @State private var result: UndoResult?
    @State private var undos = 0

    var body: some View {
        PebbleCard {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s2) {
                Label(ReviewCopy.kindLabel(record.kind), systemImage: PebbleSymbol.card(record.kind))
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.accent)
                Spacer(minLength: PebbleSpace.s2)
                Text(ReviewCopy.state(record.status))
                    .font(PebbleFont.chip)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
            // A path reads as "ThemeToggle.tsx in src/settings" to VoiceOver, not letter by letter.
            Text(verbatim: record.title)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(AppCopy.Paths.spoken(record.title) ?? record.title)
            if let detail = record.detail, !detail.isEmpty, detail != record.title {
                Text(verbatim: detail)
                    .font(PebbleFont.cardDetail)
                    .foregroundStyle(PebbleColor.secondaryText)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .accessibilityLabel(AppCopy.Paths.spoken(detail) ?? detail)
            }
            if let undo = record.undo, !record.isUndone, Self.offered(undo, by: store.bridgeOffers) {
                Button(action: run) {
                    Label(Self.label(undo), systemImage: Self.asksFaceID(undo) ? PebbleSymbol.faceID : "arrow.uturn.backward")
                }
                .buttonStyle(.pebbleSecondary)
                .disabled(isBusy)
                .accessibilityHint(Self.asksFaceID(undo) ? RecoveryCopy.Undo.hint : RecoveryCopy.Undo.gitPlanHint)
            }
            if let result {
                Text(Self.notice(result))
                    .font(PebbleFont.meta)
                    .foregroundStyle(result == .someChangesNotUndone ? PebbleColor.danger : PebbleColor.secondaryText)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isBusy {
                ProgressView()
                    .padding(PebbleSpace.s4)
                    .accessibilityLabel(AppCopy.Reviews.working)
            }
        }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(PebbleHaptics.approved, trigger: undos)
    }

    /// Pebble's button for each undo.
    static func label(_ undo: UndoOffer) -> String {
        switch undo {
        case .edit: RecoveryCopy.Undo.edit
        case .command: RecoveryCopy.Undo.command
        case .change: RecoveryCopy.Undo.change
        case .gitPlan: RecoveryCopy.Undo.gitPlan
        }
    }

    /// Pebble's notice after each.
    static func notice(_ result: UndoResult) -> String {
        switch result {
        case .editUndone: RecoveryCopy.Undo.editUndone
        case .commandUndone: RecoveryCopy.Undo.commandUndone
        case .changeUndone: RecoveryCopy.Undo.changeUndone
        case .someChangesNotUndone: RecoveryCopy.Undo.someChangesNotUndone
        case .undoPlanReady: RecoveryCopy.Undo.undoPlanReady
        }
    }

    /// Every undo but the Git plan puts files back, so it asks for Face ID.
    static func asksFaceID(_ undo: UndoOffer) -> Bool {
        if case .gitPlan = undo { false } else { true }
    }

    /// The bridge offers the undo's method.
    static func offered(_ undo: UndoOffer, by offers: (String) -> Bool) -> Bool {
        switch undo {
        case .edit, .command: offers("undo")
        case .change: offers("shell_undo")
        case .gitPlan: offers("git_plan_propose")
        }
    }

    private func run() {
        guard !isBusy else { return }
        isBusy = true
        let record = self.record
        Task {
            if let done = await store.attempt({ try await store.undo(record) }) {
                result = done
                undos += 1
            }
            isBusy = false
        }
    }
}

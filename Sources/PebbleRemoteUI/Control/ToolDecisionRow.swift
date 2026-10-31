import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A tool Pebble made and asks about: what it does, why Pebble didn't keep it on its own, Keep and Don't Keep.
struct ToolDecisionRow: View {
    let decision: ToolboxDecision
    @Environment(RemoteStore.self) private var store
    @State private var isDeciding = false

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Text(decision.name)
                .font(.headline)
            Text(decision.purpose)
                .font(PebbleFont.cardBody)
            // Each reason as Pebble's window says it: "Pebble asks because …." (App.vue's Toolbox; UX audit U-41).
            ForEach(decision.why, id: \.self) { reason in
                Text(Self.sentence(reason))
                    .font(PebbleFont.meta)
                    .foregroundStyle(.secondary)
            }
            // Side by side when they fit; stacked, Keep first, at large text sizes (as the review cards do).
            ViewThatFits(in: .horizontal) {
                HStack {
                    dontKeepButton
                    Spacer()
                    keepButton
                }
                VStack {
                    keepButton.frame(maxWidth: .infinity)
                    dontKeepButton.frame(maxWidth: .infinity)
                }
            }
            .disabled(isDeciding || !store.bridgeOffers("toolbox_decide"))
        }
        .padding(.vertical, PebbleSpace.s1)
    }

    /// Pebble's reason ("it has not been used successfully in this task yet") in Pebble's sentence, without a doubled
    /// full stop when the reason already ends with one.
    static func sentence(_ reason: String) -> String {
        var why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        while why.hasSuffix(".") { why.removeLast() }
        return AppCopy.Toolbox.asksBecause(why)
    }

    private var keepButton: some View {
        Button(AppCopy.Toolbox.keep) { decide(keep: true) }
            .buttonStyle(.pebblePrimary)
    }

    private var dontKeepButton: some View {
        Button(AppCopy.Toolbox.dontKeep) { decide(keep: false) }
            .buttonStyle(.pebbleSecondary)
    }

    private func decide(keep: Bool) {
        isDeciding = true
        Task {
            await store.attempt { try await store.decide(decision, keep: keep) }
            isDeciding = false
        }
    }
}

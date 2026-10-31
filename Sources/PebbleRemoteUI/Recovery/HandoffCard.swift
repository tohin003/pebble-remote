import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// "Continue with the new model" (ModelHandoff.vue): after the person changed the model in a conversation whose task
/// can't resume on it, Pebble can continue the conversation as a new run on the new model. It shows exactly what would
/// be sent (counts by role and route class, never contents); nothing is sent until the person approves this exact plan
/// ("Approve this handoff", with Face ID) and starts it ("Start the new run"), which opens the new conversation.
/// "Review again" reads the plan afresh; "Not now" puts the offer away. The card leads with the decision in one sentence
/// (the model, where it runs, how many messages go); Pebble's intro and plan sit under Details (UX audit U-34).
struct HandoffCard: View {
    let offer: HandoffOffer
    @Environment(RemoteStore.self) private var store
    @Environment(Router.self) private var router
    @State private var plan: HandoffPlan?
    @State private var approved = false
    @State private var started = false
    @State private var status = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var approvals = 0

    /// Pebble's window lists at most this many withheld message ids.
    private static let shownIDs = 50

    var body: some View {
        PebbleCard(emphasis: .pending) {
            Text(RecoveryCopy.Handoff.section)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.accent)
            // The decision in one sentence first: what approving and starting does (UX audit U-34).
            Text(
                AppCopy.HandoffDecision.question(
                    model: store.currentModelName, messages: plan?.total, onMac: plan?.destinationClass == "device")
            )
            .font(PebbleFont.cardTitle)
            .foregroundStyle(PebbleColor.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            if let plan, plan.uploads {
                Label(RecoveryCopy.Handoff.upload(plan.destinationClass), systemImage: "exclamationmark.triangle")
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.danger)
            }
            // Pebble's "Review what would be sent, then approve it." is what the sentence above and Details say.
            if !status.isEmpty && status != RecoveryCopy.Handoff.review {
                Text(status)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.text)
            }
            if let failure {
                Text(failure)
                    .font(PebbleFont.cardBody)
                    .foregroundStyle(PebbleColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
            if plan != nil {
                DisclosureGroup(AppCopy.HandoffDecision.details) {
                    details
                        .padding(.top, PebbleSpace.s2)
                }
                .font(PebbleFont.cardBody)
                .tint(PebbleColor.accent)
            }
        }
        .overlay(alignment: .topTrailing) {
            if busy {
                ProgressView()
                    .padding(PebbleSpace.s4)
                    .accessibilityLabel(AppCopy.Reviews.working)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RecoveryCopy.Handoff.section)
        .sensoryFeedback(PebbleHaptics.approved, trigger: approvals)
        .task(id: offer) {
            // Pebble's window reviews the plan as it opens; the phone does too unless that would ask for Face ID.
            if store.readsQuietly { await review() }
        }
    }

    /// Pebble's whole handoff, word for word, one tap away: its title and intro, then the plan, and Review Again.
    private var details: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            Text(RecoveryCopy.Handoff.title)
                .font(PebbleFont.cardBody.weight(.semibold))
                .foregroundStyle(PebbleColor.text)
            Text(RecoveryCopy.Handoff.intro)
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let plan { planView(plan) }
            Button(RecoveryCopy.Handoff.reviewAgain) { Task { await review() } }
                .buttonStyle(.pebbleSecondary)
                .disabled(busy)
        }
        .foregroundStyle(PebbleColor.text)
    }

    private func planView(_ plan: HandoffPlan) -> some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Grid(alignment: .leading, horizontalSpacing: PebbleSpace.s3, verticalSpacing: PebbleSpace.s1) {
                fact(RecoveryCopy.Handoff.from, RecoveryCopy.Handoff.className(plan.sourceClass))
                fact(RecoveryCopy.Handoff.to, RecoveryCopy.Handoff.className(plan.destinationClass))
                fact(RecoveryCopy.Handoff.destinationFingerprint, RecoveryCopy.Handoff.fingerprint(plan.destinationPrefix))
            }
            if plan.rows.isEmpty {
                Text(RecoveryCopy.Handoff.nothingSent)
                    .font(PebbleFont.cardBody)
            } else {
                Text(RecoveryCopy.Handoff.messagesSent(plan.total))
                    .font(PebbleFont.cardBody.weight(.semibold))
                Grid(alignment: .leading, horizontalSpacing: PebbleSpace.s3, verticalSpacing: PebbleSpace.s1) {
                    GridRow {
                        Text(RecoveryCopy.Handoff.role)
                        ForEach(plan.classes, id: \.self) { name in
                            Text(RecoveryCopy.Handoff.fromClass(name)).gridColumnAlignment(.trailing)
                        }
                    }
                    .font(PebbleFont.meta.weight(.semibold))
                    .foregroundStyle(PebbleColor.secondaryText)
                    ForEach(plan.rows, id: \.role) { row in
                        GridRow {
                            Text(RecoveryCopy.Handoff.role(row.role))
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, count in
                                Text(count, format: .number).monospacedDigit()
                            }
                        }
                        .font(PebbleFont.cardBody)
                    }
                }
            }
            Text(RecoveryCopy.Handoff.withheld(plan.withheld.count))
                .font(PebbleFont.cardBody)
            if !plan.withheld.isEmpty {
                DisclosureGroup(RecoveryCopy.Handoff.withheldIDs) {
                    VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                        ForEach(Array(plan.withheld.prefix(Self.shownIDs).enumerated()), id: \.offset) { _, ident in
                            Text(verbatim: ident).font(PebbleFont.code)
                        }
                        if plan.withheld.count > Self.shownIDs {
                            Text(RecoveryCopy.Handoff.andMore(plan.withheld.count - Self.shownIDs))
                        }
                    }
                }
                .font(PebbleFont.meta)
            }
            if !plan.released.isEmpty {
                Text(RecoveryCopy.Handoff.released(plan.released))
                    .font(PebbleFont.cardBody)
            }
        }
    }

    private func fact(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(PebbleColor.mutedText)
            Text(verbatim: value).foregroundStyle(PebbleColor.text).textSelection(.enabled)
        }
        .font(PebbleFont.cardBody)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if let plan {
                if store.bridgeOffers("model_handoff_approve") {
                    Button(action: approve) {
                        Label(
                            approved ? RecoveryCopy.Handoff.approved : RecoveryCopy.Handoff.approve,
                            systemImage: approved ? "checkmark" : PebbleSymbol.faceID)
                    }
                    .buttonStyle(.pebbleSecondary)
                    .disabled(busy || started || approved)
                    .accessibilityHint(RecoveryCopy.Handoff.approveHint)
                }
                if store.bridgeOffers("model_handoff_start") {
                    Button(RecoveryCopy.Handoff.start, action: { start(plan) })
                        .buttonStyle(.pebblePrimary)
                        .disabled(busy || !approved || started)
                        .accessibilityHint(RecoveryCopy.Handoff.startHint)
                }
            }
            HStack(spacing: PebbleSpace.s3) {
                // Before Pebble's plan is read (that would ask for Face ID), reviewing it is the way on.
                if plan == nil {
                    Button(RecoveryCopy.Handoff.reviewAgain) { Task { await review() } }
                        .buttonStyle(.pebbleSecondary)
                        .disabled(busy)
                }
                Button {
                    store.dismissHandoff(in: offer.chatID)
                } label: {
                    Text(RecoveryCopy.Handoff.notNow)
                        .tapTarget(alignment: .leading)
                }
                .buttonStyle(.borderless)
                .tint(PebbleColor.accent)
            }
        }
    }

    // MARK: - Calls (ModelHandoff `load`, `approve`, `start`)

    private func review() async {
        guard store.bridgeOffers("model_handoff_preview") else { return }
        busy = true
        plan = nil
        approved = false
        started = false
        failure = nil
        status = RecoveryCopy.Handoff.checking
        do {
            plan = try await store.previewHandoff(offer)
            status = RecoveryCopy.Handoff.review
        } catch {
            status = ""
            failure = store.takeNotice()
        }
        busy = false
    }

    private func approve() {
        guard let plan, !busy, !started, !approved else { return }
        busy = true
        status = ""
        failure = nil
        Task {
            if await store.attempt({ try await store.approveHandoff(plan, for: offer) }) {
                approved = true
                approvals += 1
                status = RecoveryCopy.Handoff.approvedNothingSent
            } else {
                failure = store.takeNotice()
            }
            busy = false
        }
    }

    private func start(_ plan: HandoffPlan) {
        guard approved, !busy, !started else { return }
        busy = true
        status = ""
        failure = nil
        Task {
            // A start is an effect: never repeated from here, whatever the answer.
            started = true
            approved = false
            if let chat = await store.attempt({ try await store.startHandoff(plan, for: offer) }) {
                status = RecoveryCopy.Handoff.started(on: plan.destinationClass)
                router.push(chat)
            } else {
                failure = store.takeNotice()
            }
            busy = false
        }
    }
}

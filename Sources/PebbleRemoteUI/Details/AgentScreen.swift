import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// One helper agent, chosen in Details › Task (AgentPanel.vue's selected agent, DT-21): `agent_get` reads it when it
/// opens and on pull to refresh. What a person reads first comes first (its state and use, its task, its result, as
/// Pebble's V1-111 orders them); the ids, generation, tools, limits and records are folded under Technical details.
/// Send input and Cancel agent and descendants live here, beside the agent they act on, as on the Mac.
struct AgentScreen: View {
    let agent: AgentNode
    /// Details' state: its alert shows Pebble's refusals, and its agents are read again after a change.
    let state: DetailsState
    @Environment(RemoteStore.self) private var store
    @State private var detail: AgentDetail?
    @State private var problem: String?
    @State private var busy = false
    @State private var done: String?
    @State private var isSteering = false
    @State private var input = ""
    @State private var isCancelling = false

    private var node: AgentNode { detail?.node ?? agent }

    var body: some View {
        List {
            Section {
                LabeledContent(AppCopy.Goals.status, value: AppCopy.Goals.agentStatus(node.status))
                if let used = AppCopy.Goals.used(calls: detail?.dispatches, tokens: node.tokens, seconds: node.seconds)
                {
                    Text(used)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.secondaryText)
                }
                if let error = detail?.error {
                    Text(verbatim: error)
                        .font(PebbleFont.cardBody)
                        .foregroundStyle(PebbleColor.danger)
                }
            }
            if !node.task.isEmpty {
                Section(AppCopy.Goals.task) {
                    Text(verbatim: node.task)
                        .textSelection(.enabled)
                }
            }
            if let result = node.result, !result.isEmpty {
                Section(AppCopy.Details.result) {
                    Text(verbatim: result)
                        .textSelection(.enabled)
                }
            }
            controls
            if let done {
                Section {
                    Label(done, systemImage: "checkmark.circle")
                        .font(PebbleFont.cardBody)
                }
            }
            if let detail {
                Section {
                    DisclosureGroup(AppCopy.Goals.technicalDetails) {
                        technical(detail)
                    }
                }
            } else if let problem {
                Section {
                    Text(verbatim: problem)
                        .foregroundStyle(PebbleColor.danger)
                }
            } else {
                Section {
                    Label(AppCopy.Goals.loadingAgent, systemImage: "hourglass")
                        .foregroundStyle(PebbleColor.secondaryText)
                }
            }
        }
        .navigationTitle(node.name ?? node.id)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
        .refreshable { await load() }
        .alert(AppCopy.Details.sendInputTo(node.name ?? node.id), isPresented: $isSteering) {
            TextField(AppCopy.Details.agentInput, text: $input, axis: .vertical)
            Button(AppCopy.Details.sendInput) { send(input) }
            Button(AppCopy.Common.cancel, role: .cancel) { input = "" }
        }
        .confirmationDialog(
            AppCopy.Details.cancelAgentTitle(node.name ?? node.id), isPresented: $isCancelling,
            titleVisibility: .visible
        ) {
            Button(AppCopy.Details.cancelAgent, role: .destructive, action: cancel)
        } message: {
            Text(AppCopy.Details.cancelAgentMessage)
        }
    }

    // MARK: Send input and Cancel (AgentPanel.vue: while it works, or interrupted for Cancel)

    @ViewBuilder
    private var controls: some View {
        let steers = node.isActive && store.bridgeOffers("agent_steer")
        let cancels = node.canCancel && store.bridgeOffers("agent_cancel")
        if steers || cancels {
            Section {
                if steers {
                    Button(AppCopy.Details.sendInput, systemImage: "text.bubble") {
                        input = ""
                        isSteering = true
                    }
                }
                if cancels {
                    Button(AppCopy.Details.cancelAgent, systemImage: "xmark.circle", role: .destructive) {
                        isCancelling = true
                    }
                }
            }
            .disabled(busy)
        } else if !node.canCancel {
            Section {
                Text(AppCopy.Details.readOnlyAgent)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.secondaryText)
            }
        }
    }

    // MARK: Technical details (folded)

    @ViewBuilder
    private func technical(_ detail: AgentDetail) -> some View {
        let lines = Self.technicalLines(detail)
        ForEach(lines.indices, id: \.self) { index in
            Text(verbatim: lines[index])
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
                .textSelection(.enabled)
        }
    }

    /// AgentPanel.vue's Technical details, line by line: who it is, its generation and tools, its limits, what it used,
    /// its paths and dependencies, a result kept as a record, its evidence, and how many records Pebble keeps for it.
    static func technicalLines(_ detail: AgentDetail) -> [String] {
        typealias G = AppCopy.Goals
        var lines = [
            G.identity(agent: detail.node.id, parent: detail.node.parentID),
            G.generationLine(detail.generation, tools: detail.tools, review: detail.review),
        ]
        if !detail.limits.isEmpty {
            lines.append(G.agentLimits + ": " + detail.limits.map { G.fact($0.name, $0.value) }.joined(separator: ", "))
        }
        if let accounting = G.accounting(
            dispatches: detail.dispatches, tokens: detail.node.tokens, seconds: detail.node.seconds)
        {
            lines.append(accounting)
        }
        if !detail.writePaths.isEmpty { lines.append(G.writePaths(detail.writePaths)) }
        if !detail.dependencies.isEmpty { lines.append(G.dependencies(detail.dependencies)) }
        if !detail.resultFacts.isEmpty {
            lines.append(
                G.resultRecord + ": " + detail.resultFacts.map { G.fact($0.name, $0.value) }.joined(separator: ", "))
        }
        if !detail.evidence.isEmpty { lines.append(G.evidence(detail.evidence)) }
        lines += detail.records.map { G.records($0.key, count: $0.count) }
        return lines
    }

    // MARK: Reading and changing

    private func load() async {
        guard store.bridgeOffers("agent_get") else { return }
        if let fresh = await store.attempt({ try await store.agentDetail(agent, in: state.chatID) }) {
            detail = fresh
            problem = nil
        } else {
            let words = store.takeNotice()
            if detail == nil { problem = words ?? AppCopy.Errors.generic }
        }
    }

    private func send(_ text: String) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        input = ""
        guard !words.isEmpty else { return }
        act(AppCopy.Details.inputSent) { try await store.steer(node, in: state.chatID, text: words) }
    }

    private func cancel() {
        act(AppCopy.Details.cancelRequested) { try await store.cancel(node, in: state.chatID) }
    }

    /// One change at a time; Pebble's notice when it took (shown here), its refusal in the Details alert when it
    /// didn't.
    private func act(_ words: String, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        done = nil
        Task {
            if await state.perform(store, work) != nil {
                done = words
                await state.loadAgents(store)
                await load()
            }
            busy = false
        }
    }
}

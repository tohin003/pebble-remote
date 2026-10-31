import Foundation
import PebbleProtocol

// Lane G (2026-10-31): Pebble's views on the phone (contract 3.12, pebble-ui-spec v1). The conversation's views come
// with get_chat (`artifacts`) and `artifact` events, as Pebble's window reads them (App.vue: an `artifact` event reads
// the conversation again); the work view rides the activity items Pebble already sends (`view`), and the plan rides
// the `plan` event between reads.

/// How one of the transcript's activity lines draws.
public enum WorkLine: Sendable, Hashable {
    /// The line starts a card: it and the lines after it of the same shared kind (workView.ts `workEntries`).
    case card(WorkCard<RunActivityItem>)
    /// The line is inside an earlier card, so it isn't drawn on its own.
    case folded
    /// Pebble sent a view this version can't draw: the line shows with "Update the app to see this view".
    case unreadable
}

extension PebbleWorld {
    /// `artifact {chat_id, id, …}`: a view published or updated (its whole row), stopped (its row), or a form answered
    /// (`{id, revision, status: "answered"}`). A new form carries `question_id`: its question is pending.
    mutating func artifactEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let chat = chat ?? data["chat_id"]?.string, let id = data["id"]?.string, !id.isEmpty else {
            return WorldChange()
        }
        var list = artifacts[chat] ?? []
        let index = list.firstIndex { $0.id == id }
        if data["kind"]?.string != nil, var artifact = PebbleArtifact(json: data, chatID: chat) {
            if artifact.formQuestion == nil {
                if let question = data["question_id"]?.string, !question.isEmpty {
                    artifact.formQuestion = PebbleArtifact.FormQuestion(id: question)
                } else if let index {
                    artifact.formQuestion = list[index].formQuestion
                }
            }
            if let index { list[index] = artifact } else { list.append(artifact) }
        } else if let index, data["status"]?.string == "answered" {
            list[index].formQuestion?.status = "answered"
        }
        artifacts[chat] = list
        var change = WorldChange(waiting: true)
        if timelines[chat] != nil {
            change.transcripts.insert(chat)
            // The decorated row (a form's question, a dashboard's live panels) comes with the conversation.
            change.needsChats.insert(chat)
        }
        return change
    }

    /// `plan {chat_id, run_id, revision, steps}`: the run's plan from UpdatePlan.
    mutating func planEvent(chat: ChatID?, data: JSONValue) -> WorldChange {
        guard let run = data["run_id"]?.string else { return WorldChange() }
        plans[run] = WorkPlan(json: data)
        var change = WorldChange()
        let owner = chat ?? runs[run]?.row.chatID
        if let owner, timelines[owner] != nil { change.transcripts.insert(owner) }
        return change
    }

    /// A view read from Pebble (`artifact_get`, `artifact_refresh`): it replaces the conversation's copy.
    @discardableResult
    public mutating func remember(_ artifact: PebbleArtifact) -> WorldChange {
        var list = artifacts[artifact.chatID] ?? []
        if let index = list.firstIndex(where: { $0.id == artifact.id }) {
            guard list[index].revision <= artifact.revision else { return WorldChange() }  // never an older copy
            list[index] = artifact
        } else {
            list.append(artifact)
        }
        artifacts[artifact.chatID] = list
        var change = WorldChange(waiting: true)
        if timelines[artifact.chatID] != nil { change.transcripts.insert(artifact.chatID) }
        return change
    }

    /// Pebble accepted a form's answers: its question is answered.
    @discardableResult
    public mutating func markAnswered(_ artifact: PebbleArtifact, with answers: [String: PebbleArtifact.FormAnswer])
        -> WorldChange
    {
        guard let index = artifacts[artifact.chatID]?.firstIndex(where: { $0.id == artifact.id }) else { return WorldChange() }
        artifacts[artifact.chatID]?[index].formQuestion?.status = "answered"
        artifacts[artifact.chatID]?[index].formQuestion?.answers = answers
        var change = WorldChange(waiting: true)
        if timelines[artifact.chatID] != nil { change.transcripts.insert(artifact.chatID) }
        return change
    }

    /// The form whose question this is, when the phone holds the conversation's views.
    func formArtifact(asking question: QuestionID, in chat: ChatID) -> PebbleArtifact? {
        artifacts[chat]?.last { $0.kind == "form" && $0.formQuestion?.id == question }
    }

    /// The conversation's views, oldest first.
    public func views(in chat: ChatID) -> [PebbleArtifact] { artifacts[chat] ?? [] }

    /// One view of a conversation.
    public func view(_ id: String, in chat: ChatID) -> PebbleArtifact? { artifacts[chat]?.first { $0.id == id } }

    /// How each activity line of the conversation's runs draws, by the line's id (`run/hSEQ`, as `activityItems`
    /// names Pebble's own items). Lines without an entry draw as today.
    public func workLines(for chat: ChatID) -> [String: WorkLine] {
        var lines: [String: WorkLine] = [:]
        for (run, items) in hostActivity where runs[run]?.row.chatID == chat || runs[run] == nil {
            let ordered = items.values.sorted { $0.seq < $1.seq }
            guard ordered.contains(where: { $0.view != nil || $0.hasUnreadableView }) else { continue }
            for entry in WorkEntries.group(ordered) {
                switch entry {
                case .card(let card):
                    for (offset, item) in card.items.enumerated() {
                        lines["\(run)/h\(item.seq)"] = offset == 0 ? .card(card) : .folded
                    }
                case .row(let item):
                    if item.hasUnreadableView { lines["\(run)/h\(item.seq)"] = .unreadable }
                }
            }
        }
        return lines
    }

    /// The plans of the conversation's runs.
    public func plans(for chat: ChatID) -> [RunID: WorkPlan] {
        plans.filter { runs[$0.key]?.row.chatID == chat }
    }
}

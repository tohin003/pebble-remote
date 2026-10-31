import PebbleDesign
import PebbleProtocol

/// The rules of a Pebble form's answers (NativeArtifactRenderer.vue `complete` and `submit`; interaction.canonical_answer):
/// every field answered exactly once, a choice with one of its options, a text field with words (trimmed); a form
/// takes answers only while its question is pending and the view is live.
enum FormAnswers {
    /// The answers to send, or nil while a field is unanswered.
    static func make(
        _ form: NativeView.Form, choices: [String: String], texts: [String: String]
    ) -> [String: PebbleArtifact.FormAnswer]? {
        var answers: [String: PebbleArtifact.FormAnswer] = [:]
        for field in form.fields {
            switch field.kind {
            case .choice:
                guard let chosen = choices[field.id], field.options.contains(where: { $0.id == chosen }) else { return nil }
                answers[field.id] = .option(chosen)
            case .text:
                let words = (texts[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !words.isEmpty else { return nil }
                answers[field.id] = .text(String(words.prefix(2000)))
            }
        }
        return answers
    }

    /// The answers Pebble kept, as the fields' values (a form opened again shows what was sent).
    static func values(
        _ form: NativeView.Form, from given: [String: PebbleArtifact.FormAnswer]
    ) -> (choices: [String: String], texts: [String: String]) {
        var choices: [String: String] = [:]
        var texts: [String: String] = [:]
        for field in form.fields {
            switch (field.kind, given[field.id]) {
            case (.choice, .option(let id)?) where field.options.contains(where: { $0.id == id }): choices[field.id] = id
            case (.text, .text(let words)?): texts[field.id] = words
            default: break
            }
        }
        return (choices, texts)
    }

    /// The form takes answers now.
    static func isOpen(_ artifact: PebbleArtifact) -> Bool { artifact.waitsForAnswer && artifact.form != nil }

    /// Why a form takes no answers, in Pebble's words (NativeArtifactRenderer.vue); nil while it waits for them.
    static func closedNote(_ artifact: PebbleArtifact) -> String? {
        if let status = artifact.status, status == .stopped || status == .expired {
            return AppCopy.Views.formIs(stopped: status == .stopped)
        }
        guard let question = artifact.formQuestion else { return AppCopy.Views.noActiveRequest }
        switch question.status {
        case "pending": return nil
        case "answered": return nil
        default: return AppCopy.Views.noActiveRequest
        }
    }

    /// The form's state in words, for its card and its sheet.
    static func state(_ artifact: PebbleArtifact) -> (words: String, tone: WorkTone) {
        if artifact.status == .stopped { return (AppCopy.Views.stopped, .neutral) }
        if artifact.status == .expired { return (AppCopy.Views.expired, .neutral) }
        switch artifact.formQuestion?.status {
        case "pending": return (AppCopy.Views.waitingForAnswers, .open)
        case "answered": return (AppCopy.Views.answered, .good)
        case "cancelled": return (AppCopy.Views.cancelled, .neutral)
        default: return (AppCopy.Views.kind("form"), .neutral)
        }
    }
}

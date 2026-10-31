import SwiftUI

/// A question Pebble asked (AskUserQuestion): one or more prompts, each with options and sometimes a written answer.
/// Pebble's own words: "Your answer is needed to continue." / "You can answer while other work continues.",
/// "Write an answer", "Submit Answer", "Cancel Request" or "Skip". Submit stays disabled until every prompt has an
/// answer. Options are full-width rows with a 44 pt hit region; the chosen one carries a checkmark, not only colour.
public struct QuestionCardView: View {
    /// One prompt of the question.
    public struct Prompt: Identifiable, Hashable, Sendable {
        public struct Option: Identifiable, Hashable, Sendable {
            public var id: String
            public var label: String
            public var detail: String?
            public init(id: String, label: String, detail: String? = nil) {
                self.id = id
                self.label = label
                self.detail = detail
            }
        }
        public var id: String
        public var title: String
        public var options: [Option]
        public var allowsFreeText: Bool
        public init(id: String, title: String, options: [Option], allowsFreeText: Bool) {
            self.id = id
            self.title = title
            self.options = options
            self.allowsFreeText = allowsFreeText
        }
    }

    /// One prompt's answer.
    public enum Answer: Hashable, Sendable {
        case option(id: String)
        case text(String)
    }

    let prompts: [Prompt]
    let required: Bool
    let conversation: String?
    let requester: String?
    let isBusy: Bool
    let onSend: ([String: Answer]) -> Void
    let onDismiss: () -> Void

    @State private var choices: [String: String] = [:]
    @State private var texts: [String: String] = [:]

    private static let writeChoice = "\u{0}write"

    public init(
        prompts: [Prompt], required: Bool, conversation: String?, requester: String? = nil, isBusy: Bool = false,
        onSend: @escaping ([String: Answer]) -> Void, onDismiss: @escaping () -> Void
    ) {
        self.prompts = prompts
        self.required = required
        self.conversation = conversation
        self.requester = requester
        self.isBusy = isBusy
        self.onSend = onSend
        self.onDismiss = onDismiss
    }

    public var body: some View {
        PebbleCard(emphasis: .pending) {
            Label(AppCopy.Reviews.question, systemImage: PebbleSymbol.status(.question))
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.accent)
            if let requester {
                Text(AppCopy.Reviews.requestedBy(requester))
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
            }
            ForEach(prompts) { prompt in
                QuestionPromptSection(
                    prompt: prompt, choice: $choices[prompt.id], text: $texts[prompt.id],
                    writeChoice: Self.writeChoice)
            }
            Text(required
                ? (requester == nil ? AppCopy.Reviews.answerRequired : AppCopy.Reviews.answerRequiredByAgent)
                : AppCopy.Reviews.answerOptional)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
            if let conversation {
                Label(AppCopy.Reviews.inConversation(conversation), systemImage: PebbleSymbol.conversation)
                    .font(PebbleFont.meta)
                    .foregroundStyle(PebbleColor.mutedText)
                    .lineLimit(1)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PebbleSpace.s3) {
                    dismissButton
                    Spacer(minLength: 0)
                    sendButton
                }
                VStack(spacing: PebbleSpace.s2) {
                    sendButton.frame(maxWidth: .infinity)
                    dismissButton.frame(maxWidth: .infinity)
                }
            }
            .disabled(isBusy)
            .overlay {
                if isBusy { ProgressView().accessibilityLabel(AppCopy.Reviews.working) }
            }
        }
        .sensoryFeedback(PebbleHaptics.selection, trigger: choices)
    }

    private var sendButton: some View {
        Button(AppCopy.Reviews.sendAnswer, action: send)
            .buttonStyle(.pebblePrimary)
            .disabled(!ready)
    }

    private var dismissButton: some View {
        Button(required ? AppCopy.Reviews.cancelRequest : AppCopy.Reviews.skip, action: onDismiss)
            .buttonStyle(.pebbleSecondary)
    }

    private var ready: Bool {
        prompts.allSatisfy { prompt in
            guard let choice = choices[prompt.id] else { return false }
            return choice != Self.writeChoice || !(texts[prompt.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func send() {
        var answers: [String: Answer] = [:]
        for prompt in prompts {
            guard let choice = choices[prompt.id] else { return }
            answers[prompt.id] = choice == Self.writeChoice ? .text(texts[prompt.id] ?? "") : .option(id: choice)
        }
        onSend(answers)
    }
}

/// One prompt: its title, its options as rows, and the written answer when Pebble allows one.
private struct QuestionPromptSection: View {
    let prompt: QuestionCardView.Prompt
    @Binding var choice: String?
    @Binding var text: String?
    let writeChoice: String
    @FocusState private var writing: Bool
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Text(verbatim: prompt.title)
                .font(PebbleFont.cardTitle)
                .foregroundStyle(PebbleColor.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(prompt.options) { option in
                OptionRow(label: option.label, detail: option.detail, selected: choice == option.id) {
                    choice = option.id
                }
            }
            if prompt.allowsFreeText {
                OptionRow(label: AppCopy.Reviews.otherAnswer, detail: nil, selected: choice == writeChoice) {
                    choice = writeChoice
                    writing = true
                }
                if choice == writeChoice {
                    // The keyboard always lets go (the re-check's U-54, on Reviews' tab root with no Back): Done above
                    // it, Return in an empty answer, and the list's scroll (ReviewsList).
                    TextField(AppCopy.Reviews.yourAnswer, text: $draft, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($writing)
                        .closesKeyboardOnEmptyReturn($draft, focus: $writing)
                        .padding(PebbleSpace.s3)
                        .background(PebbleColor.code, in: PebbleShapes.inset)
                        .accessibilityLabel(prompt.title)
                        .onChange(of: draft) { _, new in text = new }
                        #if os(iOS)
                        .toolbar {
                            if writing {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button(AppCopy.Common.done) { writing = false }
                                }
                            }
                        }
                        #endif
                }
            }
        }
    }
}

/// A choosable row: the label, its detail, and a checkmark when chosen. A real button (VoiceOver: "selected").
private struct OptionRow: View {
    let label: String
    let detail: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: PebbleSpace.s3) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PebbleColor.accent : PebbleColor.mutedText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: label)
                        .font(PebbleFont.message)
                        .foregroundStyle(PebbleColor.text)
                    if let detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(PebbleFont.meta)
                            .foregroundStyle(PebbleColor.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, PebbleSpace.s2)
            .padding(.horizontal, PebbleSpace.s3)
            .frame(minHeight: PebbleSize.minTap)
            .background(selected ? PebbleColor.soft : PebbleColor.panel, in: PebbleShapes.inset)
            .overlay { PebbleShapes.inset.stroke(selected ? PebbleColor.accentSoft : PebbleColor.line, lineWidth: 1) }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if os(iOS)
#Preview("Question") {
    ScrollView {
        QuestionCardView(
            prompts: [
                .init(
                    id: "beds", title: "Which beds should get the tomatoes?",
                    options: [
                        .init(id: "a", label: "The two by the fence", detail: "Most sun after noon"),
                        .init(id: "b", label: "The raised bed"),
                    ], allowsFreeText: true)
            ], required: true, conversation: "Plan the garden beds", onSend: { _ in }, onDismiss: {})
        .padding()
    }
}
#endif

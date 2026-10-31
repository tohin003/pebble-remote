import PebbleDesign
import PebbleProtocol
import SwiftUI

/// An app demo Pebble drew (PrototypeRenderer.vue): a clickable mock-up whose controls only switch between its own
/// screens. Previous Screen, a screen picker and Restart Demo above it; typing and switches stay in the preview, and
/// nothing is saved or sent. Send Feedback puts words naming the screen in the conversation's message box.
struct PrototypeBody: View {
    let prototype: NativeView.Prototype
    /// Send Feedback, with the screen on show (nil where there is no conversation to write in).
    let feedback: ((String) -> Void)?
    @State private var screenID: String
    @State private var visited: [String] = []
    @State private var fields: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]

    init(prototype: NativeView.Prototype, feedback: ((String) -> Void)? = nil) {
        self.prototype = prototype
        self.feedback = feedback
        _screenID = State(initialValue: prototype.start)
    }

    var body: some View {
        let screen = prototype.screen(screenID) ?? prototype.screens[0]
        let position = (prototype.screens.firstIndex { $0.id == screen.id } ?? 0) + 1
        VStack(alignment: .leading, spacing: PebbleSpace.s3) {
            Text(AppCopy.Views.mockUpNote)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.secondaryText)
            HStack(spacing: PebbleSpace.s2) {
                Button(AppCopy.Views.previousScreen, systemImage: ViewSymbol.back, action: back)
                    .labelStyle(.iconOnly)
                    .disabled(visited.isEmpty)
                    .frame(minWidth: PebbleSize.minTap, minHeight: PebbleSize.minTap)
                Picker(AppCopy.Views.screen, selection: screenChoice) {
                    ForEach(prototype.screens) { item in
                        Text(verbatim: item.title).tag(item.id)
                    }
                }
                .pickerStyle(.menu)
                Text(AppCopy.Views.position(position, of: prototype.screens.count))
                    .font(PebbleFont.meta.monospacedDigit())
                    .foregroundStyle(PebbleColor.secondaryText)
                Spacer(minLength: 0)
                Button(AppCopy.Views.restartDemo, systemImage: ViewSymbol.restart, action: restart)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: PebbleSize.minTap, minHeight: PebbleSize.minTap)
            }
            PrototypeScreenView(screen: screen, fields: $fields, toggles: $toggles, go: go)
            Text(AppCopy.Views.nothingSaved)
                .font(PebbleFont.meta)
                .foregroundStyle(PebbleColor.mutedText)
            if let feedback {
                VStack(alignment: .leading, spacing: PebbleSpace.s1) {
                    Button(AppCopy.Views.sendFeedback, systemImage: "text.bubble") { feedback(screen.id) }
                        .buttonStyle(.pebbleSecondary)
                    Text(AppCopy.Views.feedbackNote)
                        .font(PebbleFont.meta)
                        .foregroundStyle(PebbleColor.mutedText)
                }
            }
        }
    }

    /// The picker goes to a screen as a demo button would, so Previous Screen comes back.
    private var screenChoice: Binding<String> {
        Binding(get: { screenID }, set: { go($0) })
    }

    private func go(_ target: String?) {
        guard let target, target != screenID, prototype.screen(target) != nil else { return }
        visited.append(screenID)
        screenID = target
    }

    private func back() {
        guard let last = visited.popLast() else { return }
        screenID = last
    }

    private func restart() {
        visited = []
        fields = [:]
        toggles = [:]
        screenID = prototype.start
    }
}

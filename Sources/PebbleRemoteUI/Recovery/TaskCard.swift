import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// A conversation's task when its state needs the person, as Pebble's window says it under the conversation
/// (RunPanel.vue): the state in Pebble's sentence; a paused window's Done and End access; a held task's "Run the
/// tests", "Ask Pebble to finish" and "Accept as unverified" (after Pebble's question); Resume (after new limits when
/// the task reached its limit); and Details. Shown under the transcript, and on the Reviews tab for the two states Pebble
/// waits on. Every control shows only what Pebble confirmed: the card changes when Pebble's answer arrives.
struct TaskCard: View {
    let task: TaskAttention
    /// Shows what Pebble did in the task; nil where the screen can't (the Reviews tab).
    var showDetails: ((RunID) -> Void)? = nil
    var present: RecoveryPresenter? = nil
    var inConversation = true
    @Environment(RemoteStore.self) private var store
    @State private var busy: Step?
    @State private var isConfirmingAccept = false
    @State private var decisions = 0
    @State private var resumes = 0

    private enum Step: Equatable {
        case tests, finish, accept, resume
        case window(String)
    }

    var body: some View {
        let controls = TaskControls(
            task: task, offers: store.bridgeOffers, inConversation: inConversation, showsRunDetails: showDetails != nil)
        PebbleCard(emphasis: task.waitsForDecision ? .pending : task.state == .failed ? .problem : .plain) {
            Label {
                Text(RecoveryCopy.Task.sentence(task.state, windowChecked: task.windowChecked))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(task.state == .failed ? PebbleColor.danger : PebbleColor.accent)
            }
            .font(PebbleFont.cardTitle)
            .foregroundStyle(PebbleColor.text)
            .accessibilityAddTraits(.isHeader)
            if controls.windowDone || controls.endAccess {
                ForEach(task.pausedWindows) { window in
                    pausedWindow(window, controls: controls)
                }
            }
            if controls.holdsDecisions {
                heldDecisions(controls)
            }
            if controls.resume || controls.details != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PebbleSpace.s3) { runButtons(controls) }
                    VStack(alignment: .leading, spacing: PebbleSpace.s2) { runButtons(controls) }
                }
            }
        }
        .disabled(busy != nil)
        .overlay(alignment: .topTrailing) {
            if busy != nil {
                ProgressView()
                    .padding(PebbleSpace.s4)
                    .accessibilityLabel(AppCopy.Reviews.working)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RecoveryCopy.Task.label)
        .confirmationDialog(
            RecoveryCopy.Held.acceptQuestion, isPresented: $isConfirmingAccept, titleVisibility: .visible
        ) {
            Button(RecoveryCopy.Held.acceptAsUnverified) { run(.accept) }
            Button(RecoveryCopy.Held.cancel, role: .cancel) {}
        }
        .sensoryFeedback(PebbleHaptics.approved, trigger: decisions)
        .sensoryFeedback(PebbleHaptics.stopped, trigger: resumes)
        // The windows this step paused, read once the phone may read without asking for Face ID (C1).
        .task(id: "\(task.id)/\(store.readsQuietly)") {
            if task.needsCheck { await store.loadPausedWindows(in: task.chatID) }
        }
    }

    private var symbol: String {
        task.state.statusKey.map(PebbleSymbol.status) ?? PebbleSymbol.stopEverything
    }

    // MARK: - A paused window

    private func pausedWindow(_ window: ScreenSession, controls: TaskControls) -> some View {
        // The app as macOS names it ("Mail"), not its bundle ID's last part ("mail"; UX audit U-28).
        let app = RecoveryCopy.PausedWindow.app(AppCopy.Places.appName(bundleID: window.bundleID))
        return VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            Text(RecoveryCopy.PausedWindow.sentence(app))
                .font(PebbleFont.cardBody)
                .foregroundStyle(PebbleColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: PebbleSpace.s3) {
                if controls.windowDone {
                    Button(RecoveryCopy.PausedWindow.done) { decide(window, done: true) }
                        .buttonStyle(.pebbleSecondary)
                        .accessibilityHint(RecoveryCopy.PausedWindow.doneHint)
                }
                if controls.endAccess {
                    Button {
                        decide(window, done: false)
                    } label: {
                        Text(RecoveryCopy.PausedWindow.endAccess)
                            .tapTarget(alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .tint(PebbleColor.accent)
                    .accessibilityHint(RecoveryCopy.PausedWindow.endAccessHint)
                }
            }
        }
        .padding(PebbleSpace.s3)
        .background(PebbleColor.soft, in: PebbleShapes.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RecoveryCopy.PausedWindow.label(app))
    }

    // MARK: - A held task's three decisions

    private func heldDecisions(_ controls: TaskControls) -> some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            if controls.runTests {
                Button(RecoveryCopy.Held.runTheTests) { run(.tests) }
                    .buttonStyle(.pebbleSecondary)
                    .accessibilityHint(RecoveryCopy.Held.runTheTestsHint)
            }
            if controls.askToFinish {
                Button(RecoveryCopy.Held.askPebbleToFinish) { run(.finish) }
                    .buttonStyle(.pebbleSecondary)
                    .accessibilityHint(RecoveryCopy.Held.askPebbleToFinishHint)
            }
            if controls.accept {
                Button {
                    isConfirmingAccept = true
                } label: {
                    Label(RecoveryCopy.Held.acceptAsUnverified, systemImage: PebbleSymbol.faceID)
                        .tapTarget(alignment: .leading)
                }
                .buttonStyle(.borderless)
                .tint(PebbleColor.accent)
                .accessibilityHint(RecoveryCopy.Held.acceptHint)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RecoveryCopy.Held.title)
    }

    // MARK: - Resume and Details

    @ViewBuilder
    private func runButtons(_ controls: TaskControls) -> some View {
        if controls.resume {
            Button(
                controls.resumeAsksLimits ? RecoveryCopy.Task.resumeWithLimits : RecoveryCopy.Task.resume,
                systemImage: PebbleSymbol.resume
            ) {
                if controls.resumeAsksLimits, let present {
                    present(.limits(task))
                } else {
                    run(.resume)
                }
            }
            .buttonStyle(.pebbleSecondary)
            .accessibilityHint(RecoveryCopy.Task.resumeHint)
        }
        if let details = controls.details {
            Button {
                switch details {
                case .outcomes: present?(.outcomes(task))
                case .run: showDetails?(task.runID)
                }
            } label: {
                Text(RecoveryCopy.Task.details)
                    .tapTarget(alignment: .leading)
            }
            .buttonStyle(.borderless)
            .tint(PebbleColor.accent)
            .accessibilityHint(details == .outcomes ? RecoveryCopy.Task.outcomesHint : RecoveryCopy.Task.detailsHint)
        }
    }

    // MARK: - Calls

    private func run(_ step: Step) {
        guard busy == nil else { return }
        busy = step
        let task = self.task
        Task {
            let done = await store.attempt {
                switch step {
                case .tests: try await store.runHeldTests(task)
                case .finish: try await store.askPebbleToFinish(task)
                case .accept: try await store.acceptUnverified(task)
                case .resume: try await store.resume(task)
                case .window: break
                }
            }
            if done {
                if step == .resume { resumes += 1 } else { decisions += 1 }
            }
            busy = nil
        }
    }

    private func decide(_ window: ScreenSession, done: Bool) {
        guard busy == nil else { return }
        busy = .window(window.id)
        Task {
            if await store.attempt({ done ? try await store.markWindowDone(window) : try await store.endAccess(window) }) {
                decisions += 1
            }
            busy = nil
        }
    }
}

import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A switch whose value lives on the Mac (Keep awake, memory, the tools). It shows only what Pebble confirmed (design
/// review A2): a flip sends the change, a spinner shows while Face ID and Pebble answer, and the switch moves when the
/// store hears Pebble's new value. A declined Face ID or a refusal leaves it where it was. A change made on the Mac
/// moves it too.
struct RemoteToggle: View {
    let title: String
    var subtitle: String? = nil
    /// The Mac's value, as the store last heard it.
    let value: Bool
    /// When a change asks for Face ID; the glyph after the name says so.
    var faceID: GuardedToggle.FaceIDRule = .never
    /// False in a section whose every switch asks for Face ID and whose footer says so once (UX audit U-38): the row then
    /// shows no glyph, and VoiceOver hears it as a hint instead.
    var marksFaceID = true
    /// Sends the change and returns once the store shows Pebble's answer; returns whether the Mac took it.
    let send: (Bool) async -> Bool

    @State private var isSending = false

    init(
        _ title: String, subtitle: String? = nil, value: Bool, faceID: GuardedToggle.FaceIDRule = .never,
        marksFaceID: Bool = true, send: @escaping (Bool) async -> Bool
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.faceID = faceID
        self.marksFaceID = marksFaceID
        self.send = send
    }

    var body: some View {
        GuardedToggle(
            title, detail: subtitle, isOn: value, faceID: marksFaceID ? faceID : .never, isBusy: isSending
        ) { wanted in
            guard !isSending else { return }
            isSending = true
            Task {
                _ = await send(wanted)
                isSending = false
            }
        }
        .accessibilityHint(!marksFaceID && Self.nextAsksFaceID(faceID, isOn: value) ? AppCopy.FaceID.asksFirst : "")
    }

    /// Whether flipping the switch now asks for Face ID (GuardedToggle's rule).
    static func nextAsksFaceID(_ rule: GuardedToggle.FaceIDRule, isOn: Bool) -> Bool {
        switch rule {
        case .never: false
        case .whenTurningOn: !isOn
        case .always: true
        }
    }
}

extension RemoteStore {
    /// The footer note for a section of switches that all ask for Face ID (UX audit U-38): once, under them.
    func faceIDNote(forSetting key: String) -> String? {
        settingNeedsProof(key) ? AppCopy.Modes.changesAskForFaceID : nil
    }
}

extension RemoteStore {
    /// The Face ID rule for a switch that changes one of Pebble's settings: every change, when the bridge elevates the
    /// key (contract 3.6, `setting:<key>`).
    func faceIDRule(forSetting key: String) -> GuardedToggle.FaceIDRule {
        settingNeedsProof(key) ? .always : .never
    }
}

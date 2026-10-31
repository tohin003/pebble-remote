#if DEBUG
import PebbleRemoteKit
import SwiftUI

/// Lane U's UI audit (`docs/lanes/U-brief.md`): the launch argument `-PebbleUIAudit 1` opens the in-app demo at once,
/// for the XCUITest target `PebbleRemoteUIAudit`, which taps through every screen like a first-time user.
///
/// - **DEBUG builds only.** This file and the app's one use of it are inside `#if DEBUG`, so a Release build doesn't
///   contain them, and the argument does nothing there.
/// - **It can never reach a Mac.** Both of the audit model's stores are demo stores (a simulated Pebble on the phone), so
///   the live client and the paired Mac kept in the Keychain are never made, not even when the audit taps "Leave the
///   Demo" (a fresh demo starts instead) or opens a pairing link.
/// - **No Face ID and no app lock.** The demo agrees to every unlock and approval by itself, and the app lock never
///   applies to the demo (`PebbleRemoteModel.lockApplies`), so the run never waits on biometrics.
/// - `-PebbleUIAuditPace <n>` (optional) scales the demo's pauses: 1 is lifelike (the default), larger is slower, 0 runs
///   its scripts without waiting. A fixed pace makes a run repeat the same way.
/// - `-PebbleUIAuditAppearance dark|light` (optional) draws the app in that appearance without changing the phone's own
///   setting.
nonisolated public struct UIAuditLaunch: Equatable, Sendable {
    public enum Appearance: String, Sendable {
        case light, dark
    }

    /// The demo's pace (`RemoteStore.demo(pace:)`).
    public var pace: Double
    public var appearance: Appearance?

    /// Nil unless the arguments hold `-PebbleUIAudit 1`.
    public init?(arguments: [String]) {
        guard Self.value(of: "-PebbleUIAudit", in: arguments) == "1" else { return nil }
        let pace = Self.value(of: "-PebbleUIAuditPace", in: arguments).flatMap(Double.init)
        self.pace = pace.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 1
        appearance = Self.value(of: "-PebbleUIAuditAppearance", in: arguments).flatMap(Appearance.init(rawValue:))
    }

    /// For `preferredColorScheme`: nil follows the phone.
    public var colorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case nil: nil
        }
    }

    /// The word after the argument's name, as `UserDefaults` reads `-name value` pairs.
    static func value(of name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

extension PebbleRemoteModel {
    /// The app's model for the UI audit: the demo, and the demo again where the app would make the paired Mac's store.
    public static func uiAudit(_ launch: UIAuditLaunch) -> PebbleRemoteModel {
        let pace = launch.pace
        return PebbleRemoteModel(live: { .demo(pace: pace) }, demo: { .demo(pace: pace) }, startInDemo: true)
    }
}
#endif

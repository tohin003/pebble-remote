import PebbleRemoteUI
import SwiftUI

/// Pebble Remote's entry point: a thin shell. It owns the app's model (the store for the paired Mac or the in-app
/// demo, the Face ID lock, navigation; built in PebbleRemoteUI so the package's builds check it) and forwards
/// scene-phase changes to it: `.active` connects and asks for Face ID if locked, `.background` closes the connection
/// politely and locks. Everything else lives in the package.
///
/// Launch argument `-demo` starts in the demo (screenshots, trying the app without a Mac).
@main
struct PebbleRemoteApp: App {
    @State private var model = Self.makeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PebbleRemoteRoot(model: model)
                #if DEBUG
                .preferredColorScheme(Self.audit?.colorScheme)
                #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }

    private static func makeModel() -> PebbleRemoteModel {
        #if DEBUG
        if let audit { return .uiAudit(audit) }
        #endif
        return .standard(startInDemo: ProcessInfo.processInfo.arguments.contains("-demo"))
    }

    #if DEBUG
    /// Lane U's UI audit, `-PebbleUIAudit 1`: the demo only, never a Mac, no Face ID (`UIAuditLaunch`). DEBUG builds
    /// only: a Release build has neither this property nor the code that reads it, so the argument does nothing there.
    private static let audit = UIAuditLaunch(arguments: ProcessInfo.processInfo.arguments)
    #endif
}

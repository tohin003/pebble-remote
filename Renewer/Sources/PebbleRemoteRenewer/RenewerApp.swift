import AppKit
import RenewerCore
import SwiftUI

/// The menu-bar item (LSUIElement: no Dock icon, no windows).
/// - The bar: the days left ("5 days").
/// - The menu: the end date, what happens next, Renew Now, Renew Automatically, the last result, Quit.
struct RenewerApp: App {
    @State private var model: RenewerModel

    init() {
        let configuration = AppConfiguration.resolve(
            arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment, bundle: .main)
        let model = RenewerModel(configuration: configuration)
        _model = State(initialValue: model)
        model.start()
    }

    var body: some Scene {
        MenuBarExtra {
            RenewerMenu(model: model)
        } label: {
            BarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct BarLabel: View {
    let model: RenewerModel

    var body: some View {
        Text(model.words.bar)
    }
}

struct RenewerMenu: View {
    let model: RenewerModel

    var body: some View {
        let words = model.words
        Text(words.expiry)
        if let note = words.note {
            Text(note)
        }
        Text(words.plan)
        Divider()
        Button(Copy.renewNow) { model.renewNow() }
            .disabled(!model.canRenewNow)
        Toggle(Copy.renewAutomatically, isOn: Binding(get: { model.autoRenew }, set: { model.setAutoRenew($0) }))
        Divider()
        ForEach(words.result, id: \.self) { line in
            Text(line)
        }
        Divider()
        Button(Copy.quit) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

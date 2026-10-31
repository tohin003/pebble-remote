import SwiftUI

/// The screen for each Control route.
struct ControlDestination: View {
    let route: ControlRoute

    var body: some View {
        switch route {
        case .mode: ModePickerList()
        case .fastReplies: FastRepliesList()
        case .screenSessions: ScreenSessionsView()
        case .toolbox: ToolboxView()
        case .schedules: SchedulesView()
        case .connection: ConnectionDetailsView()
        case .models: ModelsList()
        case .effort: EffortList()
        case .pairedPhones: PairedPhonesList()
        case .memory: PebbleSettingsDestination(screen: .memory)
        case .macAppearance: PebbleSettingsDestination(screen: .appearance)
        case .notifications: PebbleSettingsDestination(screen: .notifications)
        case .extensions: ExtensionsView()
        case .dataStorage: DataStorageView()
        case .telemetry: TelemetryView()
        case .shellGrants: ShellGrantsView()
        }
    }
}

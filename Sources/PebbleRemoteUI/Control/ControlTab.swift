import SwiftUI

/// The Control tab: Pebble's settings that the phone may change, the Mac, screen sessions, Toolbox, schedules,
/// Stop everything, the connection, and Settings.
struct ControlTab: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.controlPath) {
            ControlScreen()
                .navigationDestination(for: ControlRoute.self) { route in
                    ControlDestination(route: route)
                }
        }
    }
}

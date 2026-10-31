import PebbleDesign
import PebbleProtocol
import PebbleRemoteKit
import SwiftUI

/// How Pebble looks on the Mac (not this phone): the theme, Reduce motion, and the companion's switches, with Pebble's
/// own words. The companion's settings go back to the Mac whole, with the one switch changed.
struct MacAppearanceView: View {
    let settings: PebbleSettings
    @Environment(RemoteStore.self) private var store

    var body: some View {
        Form {
            Section {
                RemoteMenuPicker(
                    AppCopy.PebbleSettings.theme, choices: Self.themes, value: settings.theme
                ) { theme in
                    await store.attempt { try await store.setTheme(theme) }
                }
                RemoteToggle(
                    AppCopy.PebbleSettings.reduceMotion, subtitle: AppCopy.PebbleSettings.reduceMotionDetail,
                    value: settings.reducedMotion, faceID: store.faceIDRule(forSetting: "reduced_motion")
                ) { on in
                    await store.attempt { try await store.setReducedMotion(on) }
                }
            }
            Section {
                RemoteToggle(
                    AppCopy.PebbleSettings.followPointer,
                    subtitle: settings.reducedMotion
                        ? AppCopy.PebbleSettings.offWhileReduced : AppCopy.PebbleSettings.followPointerDetail,
                    value: flag("pointer"), faceID: store.faceIDRule(forSetting: "companion"), marksFaceID: false
                ) { on in
                    await setCompanion("pointer", .bool(on))
                }
                .disabled(settings.reducedMotion)
                RemoteToggle(
                    AppCopy.PebbleSettings.reactions,
                    subtitle: settings.reducedMotion
                        ? AppCopy.PebbleSettings.offWhileReduced : AppCopy.PebbleSettings.reactionsDetail,
                    value: flag("reactions"), faceID: store.faceIDRule(forSetting: "companion"), marksFaceID: false
                ) { on in
                    await setCompanion("reactions", .bool(on))
                }
                .disabled(settings.reducedMotion)
                RemoteMenuPicker(
                    AppCopy.PebbleSettings.statusWords, subtitle: AppCopy.PebbleSettings.statusWordsDetail,
                    choices: Self.statusWords, value: settings.companion["status_words"]?.string ?? "rotate"
                ) { choice in
                    await setCompanion("status_words", .string(choice))
                }
                RemoteToggle(
                    AppCopy.PebbleSettings.uiGuidance, subtitle: AppCopy.PebbleSettings.uiGuidanceDetail,
                    value: flag("ui_guidance"), faceID: store.faceIDRule(forSetting: "companion"), marksFaceID: false
                ) { on in
                    await setCompanion("ui_guidance", .bool(on))
                }
            } header: {
                Text(AppCopy.PebbleSettings.companion)
            } footer: {
                // Every change here goes through Pebble's companion setting: Face ID said once (UX audit U-38).
                if let note = store.faceIDNote(forSetting: "companion") {
                    Text(note)
                }
            }
        }
        .navigationTitle(AppCopy.PebbleSettings.appearance)
    }

    private static let themes = [
        Choice(id: "system", title: AppCopy.Settings.appearanceSystem),
        Choice(id: "light", title: AppCopy.Settings.appearanceLight),
        Choice(id: "dark", title: AppCopy.Settings.appearanceDark),
    ]

    private static let statusWords = ["rotate", "fixed", "off"].map {
        Choice(id: $0, title: AppCopy.PebbleSettings.statusWordsChoice($0))
    }

    /// A companion switch; Pebble's defaults (on) when the Mac didn't say.
    private func flag(_ key: String) -> Bool {
        settings.companion[key]?.bool ?? true
    }

    private func setCompanion(_ key: String, _ value: JSONValue) async -> Bool {
        var object = settings.companion.object ?? [:]
        object[key] = value
        return await store.attempt { try await store.setCompanion(.object(object)) }
    }
}

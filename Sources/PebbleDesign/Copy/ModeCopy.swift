import PebbleProtocol

/// The permission modes' names and exact copy, word for word from Pebble's `src/permissionModes.ts` (`MODES`,
/// `MODE_IDS`, `EVERY_MODE`, `modeName`). The words say what Pebble does today in each mode; when Pebble changes what a
/// mode allows, this copy changes in the same change (`PebbleParityTests` fails until it does).
nonisolated public struct ModeCopy: Sendable, Hashable, Identifiable {
    public let mode: PermissionMode
    public let name: String
    public let runsWithoutAsking: String
    public let alwaysAsks: String

    public var id: PermissionMode { mode }

    /// `MODE_IDS`: the order Pebble shows them in.
    public static let order: [PermissionMode] = [.ask, .auto, .full]

    /// `MODES`.
    public static let modes: [PermissionMode: ModeCopy] = [
        .ask: ModeCopy(
            mode: .ask,
            name: "Ask for approval",
            runsWithoutAsking: "Nothing that changes your project or your Mac.",
            alwaysAsks: "Every edit, test run, terminal command, app launch, Git change and connector call."
        ),
        .auto: ModeCopy(
            mode: .auto,
            name: "Auto in project",
            runsWithoutAsking:
                "Edits to project files, test runs, read-only commands (ls, cat, rg and a few more), commands that stay in this project without network (Pebble copies the project first), and Git steps it can undo.",
            alwaysAsks:
                "Changes to test files your request didn't ask for, commands with network, installs or paths outside the project, Git pushes, deletions and history rewrites, app launches and connector calls."
        ),
        .full: ModeCopy(
            mode: .full,
            name: "Full access",
            runsWithoutAsking:
                "Commands that only read or make new files, and each step your messages ask for: commands (including grep and builds), installs, Git, connector calls, app launches, windows, sites, presses.",
            alwaysAsks:
                "Spending money and your hooks' reviews. A step you didn't ask for, or a delete, push or send your words don't name, doesn't run; Pebble asks after 3 in a row or 20 in a task."
        ),
    ]

    /// `EVERY_MODE`: true in every mode; shown once under the choices.
    public static let everyMode =
        "In every mode, reading project files, searching and reading the web, and creating views run without asking while their switches below are on, and signing in is yours. In Ask and Auto, connector calls, installs and every press in a Chrome tab you granted always ask; looking, typing and choosing in that tab run under your grant. Protected credentials stay blocked."

    /// The headings Pebble's Settings puts before the two lines ("Runs without asking: ...").
    public static let runsWithoutAskingHeading = "Runs without asking"
    public static let alwaysAsksHeading = "Always asks"

    /// The copy for a mode.
    public static func `for`(_ mode: PermissionMode) -> ModeCopy {
        modes[mode] ?? fallback
    }

    /// `modeName(value)`: the name of a raw mode string, or "Ask for approval" for anything unknown (Pebble's default).
    public static func name(of raw: String?) -> String {
        guard let raw, let mode = PermissionMode(rawValue: raw) else { return fallback.name }
        return self.for(mode).name
    }

    /// Every mode, in order.
    public static var all: [ModeCopy] { order.map { self.for($0) } }

    private static let fallback = ModeCopy(
        mode: .ask, name: "Ask for approval", runsWithoutAsking: "Nothing that changes your project or your Mac.",
        alwaysAsks: "Every edit, test run, terminal command, app launch, Git change and connector call.")
}

extension PermissionMode {
    /// Pebble's copy for this mode.
    nonisolated public var copy: ModeCopy { ModeCopy.for(self) }
}

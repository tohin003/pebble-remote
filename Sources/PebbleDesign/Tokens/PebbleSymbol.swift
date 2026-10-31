import PebbleProtocol

/// The SF Symbol for each of Pebble's meanings. Symbols always come with words (a label, or an accessibility label
/// for icon-only buttons); colour and symbol never carry a meaning alone. Every name here exists on iOS 26.0
/// (`SymbolTests` checks them against the system's symbol list).
nonisolated public enum PebbleSymbol {
    /// What Pebble is doing, per status key.
    public static func status(_ key: StatusKey) -> String {
        switch key {
        case .thinking: "brain"
        case .writing: "text.bubble"
        case .reading: "eyeglasses"
        case .searching: "magnifyingglass"
        case .editing: "pencil"
        case .testing: "testtube.2"
        case .running: "terminal"
        case .delegating: "person.2"
        case .viewing: "rectangle.3.group"
        case .working: "gearshape"
        case .loading: "hourglass"
        case .question: "questionmark.bubble"
        case .review: "exclamationmark.bubble"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .blocked: "nosign"
        case .uncertain: "questionmark.diamond"
        case .offline: "bolt.slash"
        case .paused: "pause.circle"
        case .error: "exclamationmark.triangle"
        case .sending: "paperplane"
        }
    }

    /// The kind of card Pebble holds for review. Unknown kinds from a newer Pebble get a neutral symbol.
    public static func card(_ kind: CardKind) -> String {
        switch kind {
        case .edit: "pencil"
        case .tests: "testtube.2"
        case .app: "arrow.up.forward.app"
        case .command: "terminal"
        case .plugin: "puzzlepiece.extension"
        case .git: "arrow.triangle.branch"
        case .worktree: "square.on.square.dashed"
        case .install: "shippingbox"
        case .shell: "apple.terminal"
        case .file: "doc"
        case .screen: "cursorarrow.click.2"
        case .screenGrant: "macwindow.badge.plus"
        case .url: "link"
        case .screenRaise: "macwindow.on.rectangle"
        case .appAction: "applescript"
        case .browserGrant: "globe"
        default: "questionmark.square"
        }
    }

    /// The permission modes.
    public static func mode(_ mode: PermissionMode) -> String {
        switch mode {
        case .ask: "hand.raised"
        case .auto: "folder.badge.gearshape"
        case .full: "lock.open"
        }
    }

    // Tabs (Apple's tab bar fills them on selection)
    public static let tabPebble = "face.smiling"
    public static let tabChats = "bubble.left.and.bubble.right"
    public static let tabReviews = "checklist"
    public static let tabControl = "slider.horizontal.3"

    /// The app's four tabs.
    public enum Tab: String, Sendable, Hashable, CaseIterable {
        case pebble, chats, reviews, control
    }

    /// The symbol for a tab.
    public static func tab(_ tab: Tab) -> String {
        switch tab {
        case .pebble: tabPebble
        case .chats: tabChats
        case .reviews: tabReviews
        case .control: tabControl
        }
    }

    // Actions
    public static let approve = "faceid"
    public static let reject = "xmark"
    public static let stop = "stop.fill"
    public static let pause = "pause.fill"
    public static let resume = "play.fill"
    public static let send = "arrow.up"
    public static let askPebble = "square.and.pencil"
    public static let stopEverything = "stop.circle"
    public static let paste = "doc.on.clipboard"
    public static let scan = "qrcode.viewfinder"
    public static let demo = "play.circle"
    public static let copy = "doc.on.doc"
    public static let revoke = "xmark.circle"
    public static let dismiss = "xmark"

    // Control and settings
    public static let keepAwake = "cup.and.heat.waves"
    public static let stealth = "eye.slash"
    public static let fastReplies = "hare"
    public static let model = "cpu"
    public static let screenSessions = "macwindow"
    public static let toolbox = "wrench.and.screwdriver"
    public static let schedules = "calendar.badge.clock"
    public static let connection = "antenna.radiowaves.left.and.right"
    public static let mac = "laptopcomputer"
    public static let settings = "gearshape"
    public static let faceID = "faceid"
    public static let expiry = "calendar.badge.exclamationmark"
    public static let conversation = "bubble.left"
    public static let project = "folder"
    public static let finished = "checkmark.circle"
    public static let screenshot = "camera.viewfinder"
    public static let share = "square.and.arrow.up"
    public static let locked = "lock"
    public static let unlocked = "lock.open"

    // Routes to the Mac
    public static let routeLocal = "wifi"
    public static let routeTailscale = "point.3.connected.trianglepath.dotted"
    public static let routeOther = "network"
    public static let routeDemo = "play.circle"
    public static let routeNone = "wifi.slash"

    /// The battery symbol for a level, in Apple's five steps, with the bolt while charging.
    public static func battery(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Every fixed name above, for the existence test.
    public static var all: [String] {
        let fixed = [
            tabPebble, tabChats, tabReviews, tabControl, approve, reject, stop, pause, resume, send, askPebble,
            stopEverything, paste, scan, demo, copy, revoke, dismiss, keepAwake, stealth, fastReplies, model,
            screenSessions, toolbox, schedules, connection, mac, settings, faceID, expiry, conversation, project,
            finished, screenshot, share, locked, unlocked, routeLocal, routeTailscale, routeOther, routeDemo, routeNone,
        ]
        let cards: [CardKind] = [
            .edit, .tests, .app, .command, .plugin, .git, .worktree, .install, .shell, .file, .screen, .screenGrant,
            .url, .screenRaise, .appAction, .browserGrant, CardKind(rawValue: "something_new"),
        ]
        let batteries = [0, 25, 50, 75, 100].map { battery(percent: $0, charging: false) } + [battery(percent: 5, charging: true)]
        return fixed + StatusKey.allCases.map(status) + cards.map(card) + PermissionMode.allCases.map(mode) + batteries
    }
}

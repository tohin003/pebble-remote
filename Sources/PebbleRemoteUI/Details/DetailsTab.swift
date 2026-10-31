import PebbleDesign
import PebbleRemoteKit

/// The tabs of Pebble's details drawer, in Pebble's order (App.vue `DRAWER_TABS`), under Pebble's names.
enum DetailsTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case activity, task, context, changes, tools, browser

    var id: String { rawValue }

    /// The tab's name (App.vue `TAB_LABELS`).
    var title: String {
        switch self {
        case .activity: AppCopy.Details.activity
        case .task: AppCopy.Details.task
        case .context: AppCopy.Details.context
        case .changes: AppCopy.Details.changes
        case .tools: AppCopy.Details.tools
        case .browser: AppCopy.Details.browser
        }
    }

    /// Its name in "More sections" (App.vue `MORE_LABELS`); Activity is never there.
    var moreTitle: String {
        switch self {
        case .activity: AppCopy.Details.activity
        case .task: AppCopy.Details.moreTask
        case .context: AppCopy.Details.moreContext
        case .changes: AppCopy.Details.moreChanges
        case .tools: AppCopy.Details.moreTools
        case .browser: AppCopy.Details.moreBrowser
        }
    }

    var symbol: String {
        switch self {
        case .activity: "list.bullet.rectangle"
        case .task: "flag"
        case .context: "gauge.with.dots.needle.50percent"
        case .changes: "arrow.uturn.backward.circle"
        case .tools: "calendar.badge.clock"
        case .browser: "globe"
        }
    }

    /// The Pebble methods behind the tab: the bridge offers the tab when it offers any of them.
    var methods: [String] {
        switch self {
        case .activity: ["run_activity"]
        case .task: ["goal_list", "agent_list"]
        case .context: ["context_inspect"]
        case .changes: ["rewind_preview"]
        case .tools: ["job_list", "screen_sessions"]
        case .browser: ["browser_extension_status", "browser_status"]
        }
    }
}

/// Which tabs show, as Pebble's drawer decides (App.vue `drawerTabs`, `moreTabs`): a tab with something to show is
/// listed; one the person opened from "More sections" stays listed while the screen is open; the rest wait in "More
/// sections". Activity is never in it, and Context only once the conversation has a task. On the phone a tab the
/// bridge doesn't offer is left out altogether, so no tab leads to a dead control.
struct DetailsListing: Equatable, Sendable {
    var listed: [DetailsTab]
    var more: [DetailsTab]

    init(has: Set<DetailsTab>, revealed: Set<DetailsTab>, hasRun: Bool, offers: (DetailsTab) -> Bool) {
        let offered = DetailsTab.allCases.filter(offers)
        listed = offered.filter { tab in
            has.contains(tab) || (tab != .activity && tab != .context && revealed.contains(tab))
        }
        let shown = Set(listed)
        more = offered.filter { tab in
            tab != .activity && (tab != .context || hasRun) && !shown.contains(tab)
        }
    }

    /// The tab to show: the one chosen while it is listed, else the first listed (App.vue `activeTab`).
    func showing(_ chosen: DetailsTab) -> DetailsTab? {
        listed.contains(chosen) ? chosen : listed.first
    }
}

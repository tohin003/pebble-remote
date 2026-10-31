import Foundation

/// The kinds of card the work view draws (workView.ts `CardKind`).
public enum WorkCardKind: String, Sendable, Hashable, CaseIterable {
    case explored, web, files, command, tests, git, window, agents, checks

    /// Consecutive items of these kinds share one card (reads and searches, edits, presses, agents); each command,
    /// test run, Git step and check keeps its own card, as they are the steps people check.
    public var isShared: Bool {
        switch self {
        case .explored, .web, .files, .window, .agents: true
        case .command, .tests, .git, .checks: false
        }
    }
}

/// What the work view needs of an activity item: its order, its status and its view.
public protocol WorkItem {
    var seq: Int { get }
    /// running, done or failed.
    var status: String { get }
    var workView: WorkView? { get }
}

/// One card: one item, or consecutive items of a shared kind, with their views in order.
public struct WorkCard<Item: WorkItem>: Identifiable {
    public var kind: WorkCardKind
    public var items: [Item]
    public var views: [WorkView]

    public init(kind: WorkCardKind, items: [Item], views: [WorkView]) {
        self.kind = kind
        self.items = items
        self.views = views
    }

    /// The first item's seq: stable while later items join.
    public var id: Int { items.first?.seq ?? 0 }

    /// A step of the card is still running.
    public var isRunning: Bool { items.contains { $0.status == "running" } }
    /// A step of the card failed.
    public var hasFailed: Bool { items.contains { $0.status == "failed" } }
}

extension WorkCard: Sendable where Item: Sendable {}
extension WorkCard: Equatable where Item: Equatable {}
extension WorkCard: Hashable where Item: Hashable {}

/// A run's items as the work view lists them: cards, and between them the items without a usable view (and review and
/// question items), which stay rows of text.
public enum WorkEntry<Item: WorkItem> {
    case card(WorkCard<Item>)
    case row(Item)
}

extension WorkEntry: Sendable where Item: Sendable {}
extension WorkEntry: Equatable where Item: Equatable {}
extension WorkEntry: Hashable where Item: Hashable {}

public enum WorkEntries {
    /// Pebble's `workEntries`, step for step: each item with a view of a card kind starts a card, or joins the card
    /// just before it when both are of the same shared kind; any other item is a row and ends the run of cards.
    public static func group<Item: WorkItem>(_ items: [Item]) -> [WorkEntry<Item>] {
        var out: [WorkEntry<Item>] = []
        for item in items {
            guard let view = item.workView, let kind = view.cardKind else {
                out.append(.row(item))
                continue
            }
            if case .card(var last)? = out.last, last.kind == kind, kind.isShared {
                last.items.append(item)
                last.views.append(view)
                out[out.count - 1] = .card(last)
            } else {
                out.append(.card(WorkCard(kind: kind, items: [item], views: [view])))
            }
        }
        return out
    }
}

// MARK: - What a card holds, as data (the words are the screens')

extension WorkCard {
    /// One changed file of a files card: its counts summed over the card (WorkCard.vue `files`).
    public struct FileChange: Sendable, Hashable, Identifiable {
        /// Nil for a private file, whose name is never sent.
        public var path: String?
        public var added: Int
        public var removed: Int
        public var state: WorkState?
        public var isNew: Bool
        public let id: String
    }

    /// The card's file changes, one per path in the order they first appear.
    public var fileChanges: [FileChange] {
        var order: [String] = []
        var byKey: [String: FileChange] = [:]
        for (index, view) in views.enumerated() {
            guard case .edit(let edit) = view.content else { continue }
            let key = edit.path ?? "private-\(index)"
            var change = byKey[key] ?? FileChange(path: edit.path, added: 0, removed: 0, state: nil, isNew: false, id: key)
            if byKey[key] == nil { order.append(key) }
            change.added += edit.added ?? 0
            change.removed += edit.removed ?? 0
            change.state = edit.state ?? change.state
            change.isNew = edit.isNew
            byKey[key] = change
        }
        return order.compactMap { byKey[$0] }
    }

    /// Lines added and removed over the card's edits (workView.ts `diffWords`).
    public var diff: (added: Int, removed: Int) {
        views.reduce(into: (added: 0, removed: 0)) { total, view in
            if case .edit(let edit) = view.content {
                total.added += edit.added ?? 0
                total.removed += edit.removed ?? 0
            }
        }
    }

    /// How many reads and how many searches an explored card holds.
    public var exploredCounts: (reads: Int, searches: Int) {
        let reads = views.filter { if case .read = $0.content { true } else { false } }.count
        return (reads, views.count - reads)
    }

    /// The web card's queries and its sites, each site once.
    public var webQueries: [String] {
        views.compactMap { if case .web(let web) = $0.content { web.query } else { nil } }
    }

    public var webSites: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for view in views {
            guard case .web(let web) = view.content else { continue }
            for site in web.sites where seen.insert(site).inserted { out.append(site) }
        }
        return out
    }
}

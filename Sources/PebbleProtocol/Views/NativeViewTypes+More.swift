import Foundation

// The native kinds a person explores (quiz, diagram, dashboard, prototype), with the bounds of `$defs/native.<kind>`.

extension NativeView {
    /// 1 to 50 questions with 2 to 6 choices. Pebble keeps the answer and the explanation out of the view it shows, so
    /// they are never read here, even when a view carries them.
    public struct Quiz: Sendable, Hashable {
        public struct Question: Sendable, Hashable, Identifiable {
            public var id: String
            public var question: String
            public var choices: [String]
        }

        public var durationMinutes: Int
        public var questions: [Question]

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let minutes = data.count("duration_minutes"), (1...180).contains(minutes),
                let list = data.list("questions"), !list.isEmpty
            else { return nil }
            var questions: [Question] = []
            for (index, value) in list.prefix(50).enumerated() {
                guard let entry = ViewFields(value), let words = entry.text("question", 1500, multiline: true),
                    let choices = entry.list("choices"), choices.count >= 2
                else { return nil }
                let shown = choices.prefix(6).compactMap { $0.string.flatMap { ViewText.clamp($0, 700, multiline: true) } }
                guard shown.count == min(choices.count, 6) else { return nil }
                questions.append(Question(id: entry.identifier("id") ?? "q\(index)", question: words, choices: shown))
            }
            durationMinutes = minutes
            self.questions = questions
        }
    }

    /// 1 to 40 nodes and up to 80 labelled edges between them.
    public struct Diagram: Sendable, Hashable {
        public struct Node: Sendable, Hashable, Identifiable {
            public var id: String
            public var label: String
        }
        public struct Edge: Sendable, Hashable, Identifiable {
            public var id: Int
            public var from: String
            public var to: String
            public var label: String?
        }

        public var nodes: [Node]
        public var edges: [Edge]

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("nodes"), !list.isEmpty else { return nil }
            var nodes: [Node] = []
            var ids = Set<String>()
            for value in list.prefix(40) {
                guard let id = value["id"]?.string, (1...60).contains(id.count), ids.insert(id).inserted,
                    let label = ViewFields(value)?.text("label", 180, multiline: true)
                else { return nil }
                nodes.append(Node(id: id, label: label))
            }
            var edges: [Edge] = []
            for (index, value) in (data.list("edges") ?? []).prefix(80).enumerated() {
                // An edge to a node the view doesn't hold is left out, never drawn to nowhere.
                guard let from = value["from"]?.string, let to = value["to"]?.string, ids.contains(from), ids.contains(to)
                else { continue }
                edges.append(Edge(id: index, from: from, to: to, label: ViewFields(value)?.text("label", 100)))
            }
            self.nodes = nodes
            self.edges = edges
        }
    }

    /// 1 to 8 panels (metric, table, chart, plan or evidence), each with its own data or a binding Pebble resolves to
    /// counts from this conversation.
    public struct Dashboard: Sendable, Hashable {
        public enum Content: Sendable, Hashable {
            case metric(Metric)
            case table(Table)
            case chart(Chart)
            case plan(Plan)
            case evidence(Evidence)
        }
        public enum State: Sendable, Hashable {
            case ready(Content)
            /// A live panel Pebble hasn't read yet ("Refresh Data" loads it).
            case waiting
            /// Pebble couldn't read the live panel; its own words, when it sent some.
            case failed(String?)
            /// The panel's data failed its checks.
            case invalid
        }
        public struct Panel: Sendable, Hashable, Identifiable {
            public var id: String
            public var title: String?
            /// metric, table, chart, plan or evidence.
            public var kind: String
            /// The source of a live panel ("runs.recent"); nil for a snapshot.
            public var source: String?
            /// When Pebble read a live panel's data.
            public var asOf: Date?
            public var state: State

            public var isLive: Bool { source != nil }
        }

        /// 1, 2 or 3 (the phone shows one column below a regular width).
        public var columns: Int
        public var panels: [Panel]

        public static let panelKinds: Set<String> = ["metric", "table", "chart", "plan", "evidence"]

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("panels"), !list.isEmpty else { return nil }
            var panels: [Panel] = []
            var ids = Set<String>()
            for value in list.prefix(8) {
                guard let entry = ViewFields(value), let id = entry.identifier("id"), ids.insert(id).inserted,
                    let kind = entry.object["kind"]?.string
                else { return nil }
                let title = entry.text("title", 120)
                let source = entry.nested("binding")?.text("source", 40)
                let state: State
                if !Self.panelKinds.contains(kind) {
                    state = .invalid
                } else if source != nil {
                    state = .waiting
                } else {
                    state = Self.content(kind: kind, data: entry.object["data"]).map(State.ready) ?? .invalid
                }
                panels.append(Panel(id: id, title: title, kind: kind, source: source, asOf: nil, state: state))
            }
            columns = data.count("columns").map { min(3, max(1, $0)) } ?? 1
            self.panels = panels
        }

        static func content(kind: String, data: JSONValue?) -> Content? {
            switch kind {
            case "metric": Metric(data).map(Content.metric)
            case "table": Table(data).map(Content.table)
            case "chart": Chart(data).map(Content.chart)
            case "plan": Plan(data).map(Content.plan)
            case "evidence": Evidence(data).map(Content.evidence)
            default: nil
            }
        }

        /// The live panels filled from what Pebble read for them (`artifact_get`'s `bindings`: `{panel_id, source,
        /// as_of, digest, data, error}`). A result for another source than the panel's is ignored.
        public func resolving(_ bindings: JSONValue?) -> Dashboard {
            guard let results = bindings?.array, !results.isEmpty else { return self }
            var copy = self
            for index in copy.panels.indices {
                let panel = copy.panels[index]
                guard let source = panel.source,
                    let result = results.first(where: { $0["panel_id"]?.string == panel.id }),
                    result["source"]?.string == source
                else { continue }
                if let failure = result["error"]?.string {
                    copy.panels[index].state = .failed(ViewText.clamp(failure, 300))
                } else if let content = Self.content(kind: panel.kind, data: result["data"]) {
                    copy.panels[index].state = .ready(content)
                    if let seconds = result["as_of"]?.double, seconds.isFinite, seconds > 0 {
                        copy.panels[index].asOf = Date(timeIntervalSince1970: seconds)
                    }
                } else {
                    copy.panels[index].state = .invalid
                }
            }
            return copy
        }

        public var liveCount: Int { panels.filter(\.isLive).count }
    }

    /// An app demo: 1 to 12 screens of up to 30 components, whose controls only switch screens. Typing and switches
    /// stay in the preview; nothing is saved or sent.
    public struct Prototype: Sendable, Hashable {
        public struct Link: Sendable, Hashable {
            public var label: String
            /// The screen it opens; nil when it names no screen of this demo.
            public var target: String?
        }
        public enum Component: Sendable, Hashable {
            case heading(String)
            case button(Link)
            case input(label: String, placeholder: String?)
            case toggle(String)
            case list([String])
            case card(title: String, body: String)
            /// Width over height, from the model's aspect ("16:9"); nil for a square.
            case image(label: String, ratio: Double?)
            case nav([Link])
        }
        public struct Screen: Sendable, Hashable, Identifiable {
            public var id: String
            public var title: String
            public var components: [Component]
        }

        public var start: String
        public var screens: [Screen]
        /// phone, tablet or desktop.
        public var viewport: String?

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("screens"), !list.isEmpty else { return nil }
            var ids: [String] = []
            for value in list.prefix(12) {
                guard let id = ViewFields(value)?.identifier("id"), !ids.contains(id) else { return nil }
                ids.append(id)
            }
            let known = Set(ids)
            screens = zip(ids, list.prefix(12)).map { id, value -> Screen in
                let entry = ViewFields(value)
                let parts = (entry?.list("components") ?? []).prefix(30).compactMap { Self.component($0, screens: known) }
                return Screen(id: id, title: entry?.text("title", 120) ?? id, components: parts)
            }
            let first = data.identifier("start")
            start = first.flatMap { known.contains($0) ? $0 : nil } ?? ids[0]
            viewport = data.text("viewport", 16)
        }

        static func component(_ value: JSONValue, screens: Set<String>) -> Component? {
            guard let entry = ViewFields(value), let type = entry.object["type"]?.string else { return nil }
            func link(_ row: ViewFields?, limit: Int) -> Link? {
                guard let row, let label = row.text("label", limit) else { return nil }
                return Link(label: label, target: row.identifier("goto").flatMap { screens.contains($0) ? $0 : nil })
            }
            switch type {
            case "heading": return entry.text("text", 240).map(Component.heading)
            case "button": return link(entry, limit: 240).map(Component.button)
            case "input":
                guard let label = entry.text("label", 240) else { return nil }
                return .input(label: label, placeholder: entry.text("placeholder", 240))
            case "toggle": return entry.text("label", 240).map(Component.toggle)
            case "list": return .list(entry.texts("items", max: 30, limit: 240) ?? [])
            case "card":
                guard let title = entry.text("title", 240) else { return nil }
                return .card(title: title, body: entry.text("body", 2000, multiline: true) ?? "")
            case "image_placeholder":
                guard let label = entry.text("label", 240) else { return nil }
                return .image(label: label, ratio: entry.object["aspect"]?.string.flatMap(Self.ratio))
            case "nav":
                let links = (entry.list("items") ?? []).prefix(8).compactMap { link(ViewFields($0), limit: 120) }
                return links.isEmpty ? nil : .nav(links)
            default: return nil
            }
        }

        static func ratio(_ aspect: String) -> Double? {
            let parts = aspect.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
            return parts[0] / parts[1]
        }

        public func screen(_ id: String) -> Screen? { screens.first { $0.id == id } }
    }
}

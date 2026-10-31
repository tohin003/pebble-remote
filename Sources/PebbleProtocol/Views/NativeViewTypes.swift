import Foundation

// The native kinds a person reads or answers (form, table, chart, plan, evidence, and the dashboard's metric), with the
// bounds of `$defs/native.<kind>`.

extension NativeView {
    /// 1 to 3 required fields, text or choice. A form is a question in disguise: its answers become task input.
    public struct Form: Sendable, Hashable {
        public struct Option: Sendable, Hashable, Identifiable {
            public var id: String
            public var label: String
        }
        public struct Field: Sendable, Hashable, Identifiable {
            public enum Kind: String, Sendable, Hashable { case text, choice }
            public var id: String
            public var label: String
            public var kind: Kind
            /// 2 to 6 options for a choice; none for text.
            public var options: [Option]
            public var placeholder: String?
        }

        public var fields: [Field]
        public var description: String?
        /// The form's own words for its button; the screen says "Submit answers" without them.
        public var submitLabel: String?

        /// Nil when any field can't be answered as sent: Pebble wants every field answered exactly once.
        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("fields"), !list.isEmpty else { return nil }
            var fields: [Field] = []
            var ids = Set<String>()
            for value in list.prefix(3) {
                guard let entry = ViewFields(value), let id = entry.identifier("id"), ids.insert(id).inserted,
                    let label = entry.text("label", 240, multiline: true), let kind: Field.Kind = entry.word("type")
                else { return nil }
                var options: [Option] = []
                if kind == .choice {
                    guard let raw = entry.list("options"), raw.count >= 2 else { return nil }
                    var optionIDs = Set<String>()
                    for option in raw.prefix(6) {
                        guard let row = ViewFields(option), let optionID = row.identifier("id"),
                            optionIDs.insert(optionID).inserted, let words = row.text("label", 120)
                        else { return nil }
                        options.append(Option(id: optionID, label: words))
                    }
                }
                fields.append(
                    Field(id: id, label: label, kind: kind, options: options, placeholder: entry.text("placeholder", 240)))
            }
            self.fields = fields
            description = data.text("description", 1500, multiline: true)
            submitLabel = data.text("submit_label", 80)
        }
    }

    /// 1 to 12 columns, up to 200 rows of primitives.
    public struct Table: Sendable, Hashable {
        public struct Column: Sendable, Hashable, Identifiable {
            public var id: String
            public var label: String
        }
        public struct Row: Sendable, Hashable, Identifiable {
            /// The row's place in the table.
            public var id: Int
            /// One cell per column, in the columns' order.
            public var cells: [ViewCell]
        }

        public var columns: [Column]
        public var rows: [Row]
        public var caption: String?

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("columns"), !list.isEmpty else { return nil }
            var columns: [Column] = []
            var ids = Set<String>()
            for value in list.prefix(12) {
                guard let entry = ViewFields(value), let id = entry.identifier("id"), ids.insert(id).inserted else {
                    return nil
                }
                columns.append(Column(id: id, label: entry.text("label", 120) ?? id))
            }
            let raw = data.list("rows") ?? []
            rows = raw.prefix(200).enumerated().map { index, value in
                Row(id: index, cells: columns.map { ViewCell(value[$0.id]) })
            }
            self.columns = columns
            caption = data.text("caption", 1000, multiline: true)
        }
    }

    /// 1 to 6 numeric series over 1 to 200 rows. Version 1 describes bar and line; Pebble 1.9.29 also draws area,
    /// scatter, stacked, pie and donut, which the phone draws too.
    public struct Chart: Sendable, Hashable {
        public enum Style: String, Sendable, Hashable, CaseIterable {
            case bar, line, area, scatter, stacked, pie, donut
        }
        public enum Format: String, Sendable, Hashable { case number, percent, compact }
        public struct Row: Sendable, Hashable, Identifiable {
            public var id: Int
            /// The row's value on the x axis.
            public var x: ViewCell
            /// One value per series, in `yKeys`' order.
            public var values: [Double]
        }

        public var style: Style
        public var xKey: String
        public var yKeys: [String]
        public var rows: [Row]
        /// Names for the keys, when the model gave them.
        public var labels: [String: String]
        public var caption: String?
        public var format: Format?
        public var unit: String?

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let style: Style = data.word("type"), let xKey = data.identifier("x_key"),
                let keyList = data.list("y_keys"), let rowList = data.list("rows"), !rowList.isEmpty
            else { return nil }
            var keys: [String] = []
            for value in keyList.prefix(6) {
                guard let key = value.string.flatMap({ ViewFields.checkedIdentifier($0) }), key != xKey, !keys.contains(key) else {
                    return nil
                }
                keys.append(key)
            }
            guard !keys.isEmpty else { return nil }
            var rows: [Row] = []
            for (index, value) in rowList.prefix(200).enumerated() {
                guard value.object != nil else { return nil }
                var numbers: [Double] = []
                for key in keys {
                    guard let number = value[key].flatMap({ ViewFields.finite($0) }) else { return nil }
                    numbers.append(number)
                }
                rows.append(Row(id: index, x: ViewCell(value[xKey]), values: numbers))
            }
            switch style {
            case .pie, .donut:
                guard keys.count == 1, (2...8).contains(rows.count), rows.allSatisfy({ $0.values[0] >= 0 }) else { return nil }
            case .stacked:
                guard rows.allSatisfy({ $0.values.allSatisfy { $0 >= 0 } }) else { return nil }
            case .scatter:
                guard rows.allSatisfy({ $0.x.number != nil }) else { return nil }
            case .bar, .line, .area:
                break
            }
            var labels: [String: String] = [:]
            for (key, value) in data.object["labels"]?.object ?? [:] where key == xKey || keys.contains(key) {
                if let words = value.string.flatMap({ ViewText.clamp($0, 120) }) { labels[key] = words }
            }
            self.style = style
            self.xKey = xKey
            yKeys = keys
            self.rows = rows
            self.labels = labels
            caption = data.text("caption", 1000, multiline: true)
            format = data.word("format")
            unit = data.text("unit", 12)
        }

        /// A key's name: the model's label, else the key itself.
        public func name(of key: String) -> String { labels[key] ?? key }
    }

    /// 1 to 20 steps, with one in progress.
    public struct Plan: Sendable, Hashable {
        public struct Step: Sendable, Hashable, Identifiable {
            public var id: String
            public var title: String
            public var status: WorkPlan.Status
            /// The steps of the task the step's evidence came from.
            public var evidenceIDs: [String]
        }

        public var steps: [Step]

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("steps"), !list.isEmpty else { return nil }
            var steps: [Step] = []
            var ids = Set<String>()
            for value in list.prefix(20) {
                guard let entry = ViewFields(value), let id = entry.identifier("id"), ids.insert(id).inserted,
                    let title = entry.text("title", 240, multiline: true), let status: WorkPlan.Status = entry.word("status")
                else { return nil }
                steps.append(
                    Step(id: id, title: title, status: status, evidenceIDs: entry.texts("evidence_ids", max: 32, limit: 350) ?? []))
            }
            self.steps = steps
        }
    }

    /// 1 to 30 items, each citing a step of the task.
    public struct Evidence: Sendable, Hashable {
        public struct Item: Sendable, Hashable, Identifiable {
            public var id: String
            public var label: String
            /// The step it cites ("3:call_tests").
            public var evidenceID: String
            public var summary: String?
        }

        public var items: [Item]
        public var caption: String?

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let list = data.list("items"), !list.isEmpty else { return nil }
            var items: [Item] = []
            var ids = Set<String>()
            for value in list.prefix(30) {
                guard let entry = ViewFields(value), let id = entry.identifier("id"), ids.insert(id).inserted,
                    let label = entry.text("label", 240, multiline: true), let cited = entry.text("evidence_id", 350)
                else { return nil }
                items.append(
                    Item(id: id, label: label, evidenceID: cited, summary: entry.text("summary", 2000, multiline: true)))
            }
            self.items = items
            caption = data.text("caption", 1000, multiline: true)
        }
    }

    /// A dashboard's metric panel: one number, its unit, its change and a caption.
    public struct Metric: Sendable, Hashable {
        public var value: Double
        public var unit: String?
        public var delta: Double?
        public var caption: String?

        init?(_ data: JSONValue?) {
            guard let data = ViewFields(data), let value = data.number("value") else { return nil }
            self.value = value
            unit = data.text("unit", 24)
            delta = data.number("delta")
            caption = data.text("caption", 240, multiline: true)
        }
    }
}

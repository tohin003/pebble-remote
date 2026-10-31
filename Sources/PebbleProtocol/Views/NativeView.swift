import Foundation

/// A view a model drew with `UIRender`, as data (pebble-ui-spec v1, "Native kinds"): Pebble stores it as an artifact of
/// its conversation and the phone draws it natively, never running code or HTML from it.
///
/// Each kind is checked against `$defs/native.<kind>`: a list past its bound keeps its first items, every string is
/// display text clamped to its bound, and fields this version does not know are ignored (rule 2). Data missing what
/// its kind needs (a chart's rows, a form's fields) is `.unsupported`, as is a kind this version does not draw yet:
/// the screen then shows the view's title with "Update the app to see this view" (rule 1).
public enum NativeView: Sendable, Hashable {
    case form(Form)
    case table(Table)
    case chart(Chart)
    case plan(Plan)
    case evidence(Evidence)
    case quiz(Quiz)
    case diagram(Diagram)
    case dashboard(Dashboard)
    case prototype(Prototype)
    /// `html`: drawn only on the Mac (`x-pebble-surfaces: ["mac"]`). The phone never draws it.
    case macOnly
    /// A kind this version does not draw, or data that failed its checks.
    case unsupported

    /// The kinds `artifact_schema.py` defines (`x-pebble-native-kinds`).
    public static let kinds = ["quiz", "diagram", "html", "form", "table", "chart", "plan", "evidence", "dashboard", "prototype"]

    public init(kind: String, data: JSONValue?) {
        switch kind {
        case "form": self = Form(data).map(NativeView.form) ?? .unsupported
        case "table": self = Table(data).map(NativeView.table) ?? .unsupported
        case "chart": self = Chart(data).map(NativeView.chart) ?? .unsupported
        case "plan": self = Plan(data).map(NativeView.plan) ?? .unsupported
        case "evidence": self = Evidence(data).map(NativeView.evidence) ?? .unsupported
        case "quiz": self = Quiz(data).map(NativeView.quiz) ?? .unsupported
        case "diagram": self = Diagram(data).map(NativeView.diagram) ?? .unsupported
        case "dashboard": self = Dashboard(data).map(NativeView.dashboard) ?? .unsupported
        case "prototype": self = Prototype(data).map(NativeView.prototype) ?? .unsupported
        case "html": self = .macOnly
        default: self = .unsupported
        }
    }

    /// The view draws on the phone.
    public var isDrawn: Bool {
        switch self {
        case .macOnly, .unsupported: false
        default: true
        }
    }
}

/// A value in a table cell or on a chart's axis: a primitive, shown as text (NativeArtifactRenderer `cell`).
public enum ViewCell: Sendable, Hashable {
    case text(String)
    case number(Double)
    case flag(Bool)
    case empty

    init(_ value: JSONValue?) {
        switch value {
        case .string(let text)?: self = ViewText.clamp(text, 2000, multiline: true).map(ViewCell.text) ?? .empty
        case .int(let number)?: self = .number(Double(number))
        case .double(let number)? where number.isFinite && abs(number) <= 1e100: self = .number(number)
        case .bool(let flag)?: self = .flag(flag)
        default: self = .empty
        }
    }

    /// As Pebble's window prints it: whole numbers without a decimal point, true and false as words of JSON. Nil for an
    /// empty cell (the screen shows a dash).
    public var plain: String? {
        switch self {
        case .text(let text): text
        case .number(let number): Self.plain(number)
        case .flag(let flag): flag ? "true" : "false"
        case .empty: nil
        }
    }

    public var number: Double? {
        if case .number(let number) = self { number } else { nil }
    }

    /// JavaScript's `String(number)` for the numbers views carry.
    public static func plain(_ number: Double) -> String {
        if number.rounded() == number, abs(number) < 1e15 { return String(Int(number)) }
        return String(number)
    }
}

import Foundation
import PebbleProtocol

// Lane T (2026-10-31): Pebble's verified exports of a view (exports.py `preview`, `render`, `list`, `get`;
// ExportPanel.vue `readReceipt`). Pebble makes the file on the Mac and reads it back; the phone sees what Pebble
// reports about it, never the file itself (no bridge method returns its bytes).

/// The formats Pebble's export section offers, in its order (ExportPanel.vue `FORMATS`; no PDF since Phase 30).
public enum ExportFormat: String, CaseIterable, Sendable, Hashable, Identifiable {
    case html, docx, xlsx, csv

    public var id: String { rawValue }
}

/// A reviewed export: what Create file will make (`export_preview`'s answer). A plan is used once, and only for the
/// revision, format and options it pinned.
public struct ExportPlan: Sendable, Hashable, Identifiable {
    public var id: String
    public var format: String
    public var revision: Int?
    public var pages: Int?
    /// When Pebble forgets the preview (10 minutes after it was made).
    public var deadline: Date?

    public init(id: String, format: String, revision: Int? = nil, pages: Int? = nil, deadline: Date? = nil) {
        self.id = id
        self.format = format
        self.revision = revision
        self.pages = pages
        self.deadline = deadline
    }

    public init?(json: JSONValue, asked format: ExportFormat) {
        guard let id = json["plan_id"]?.string, !id.isEmpty else { return nil }
        self.init(
            id: id, format: json["format"]?.string ?? format.rawValue, revision: json["source"]?["revision"]?.int,
            pages: json["pages_estimate"]?.int,
            deadline: json["deadline"]?.double.map { Date(timeIntervalSince1970: $0) })
    }
}

/// One readback check (exports.py `checks`).
public struct ExportCheck: Sendable, Hashable, Identifiable {
    public var name: String
    public var label: String
    public var passed: Bool
    public var detail: String

    public var id: String { name }

    public init(name: String, label: String, passed: Bool, detail: String = "") {
        self.name = name
        self.label = label
        self.passed = passed
        self.detail = detail
    }
}

/// A copy saved from the Mac (`export_get`'s `saves`): where the person put it, and whether it matches the export.
public struct ExportSave: Sendable, Hashable, Identifiable {
    public var id: String
    public var state: String
    /// The place the person chose in the Mac's Save dialog (their own path).
    public var path: String
    public var sha256: String
    public var verified: Bool

    public init(id: String, state: String, path: String, sha256: String = "", verified: Bool = false) {
        self.id = id
        self.state = state
        self.path = path
        self.sha256 = sha256
        self.verified = verified
    }
}

/// What Create file made and read back (`export_render`'s answer; `export_get` adds the saves, `export_list` keeps
/// only some fields): the verdict, its checks, and the file Pebble keeps.
public struct ExportResult: Sendable, Hashable, Identifiable {
    public var id: String
    public var format: String
    /// verified, unverified, unavailable, failed, cancelled, discarded (or rendering, while Pebble works).
    public var status: String
    public var reason: String?
    public var title: String?
    public var revision: Int?
    public var checks: [ExportCheck]
    /// The checks that didn't pass, by name (all `export_list` keeps of them).
    public var failedChecks: [String]
    public var notes: [String]
    public var suggestedName: String?
    public var bytes: Int?
    public var sha256: String?
    public var sheets: Int?
    public var pages: Int?
    /// How much of the source's text was found in the file, 0 to 1.
    public var coverage: Double?
    public var created: Date?
    public var saves: [ExportSave]

    public init(
        id: String, format: String, status: String, reason: String? = nil, title: String? = nil, revision: Int? = nil,
        checks: [ExportCheck] = [], failedChecks: [String] = [], notes: [String] = [], suggestedName: String? = nil,
        bytes: Int? = nil, sha256: String? = nil, sheets: Int? = nil, pages: Int? = nil, coverage: Double? = nil,
        created: Date? = nil, saves: [ExportSave] = []
    ) {
        self.id = id
        self.format = format
        self.status = status
        self.reason = reason
        self.title = title
        self.revision = revision
        self.checks = checks
        self.failedChecks = failedChecks
        self.notes = notes
        self.suggestedName = suggestedName
        self.bytes = bytes
        self.sha256 = sha256
        self.sheets = sheets
        self.pages = pages
        self.coverage = coverage
        self.created = created
        self.saves = saves
    }

    public init?(json: JSONValue) {
        guard let id = json["export_id"]?.string, !id.isEmpty else { return nil }
        let file = json["file"]
        let readback = json["readback"]
        self.init(
            id: id, format: json["format"]?.string ?? "", status: json["status"]?.string ?? "failed",
            reason: json["reason"]?.string.flatMap { $0.isEmpty ? nil : $0 }, title: json["title"]?.string,
            revision: json["source"]?["revision"]?.int,
            checks: (json["checks"]?.array ?? []).compactMap { check in
                guard let name = check["name"]?.string else { return nil }
                let label = check["label"]?.string ?? ""
                return ExportCheck(
                    name: name, label: label.isEmpty ? name : label, passed: check["passed"]?.bool == true,
                    detail: check["detail"]?.string ?? "")
            },
            failedChecks: (json["failed_checks"]?.array ?? []).compactMap(\.string),
            notes: (json["notes"]?.array ?? []).compactMap(\.string), suggestedName: file?["suggested_name"]?.string,
            bytes: file?["bytes"]?.int, sha256: file?["sha256"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            sheets: readback?["sheets"]?.int, pages: readback?["pages"]?.int,
            coverage: readback?["text_coverage"]?.double,
            created: json["created"]?.double.map { Date(timeIntervalSince1970: $0) },
            saves: (json["saves"]?.array ?? []).compactMap { save in
                guard let id = save["id"]?.string else { return nil }
                return ExportSave(
                    id: id, state: save["state"]?.string ?? "", path: save["path"]?.string ?? "",
                    sha256: save["sha256"]?.string ?? "", verified: save["verified"]?.bool == true)
            })
    }

    /// Pebble keeps a file for it, which the Mac can save and Delete Pebble's copy removes (ExportPanel.vue
    /// `savable`).
    public var keepsFile: Bool { ["verified", "unverified"].contains(status) && sha256 != nil }
}

extension PebbleArtifact {
    /// Pebble exports every view but a connector's media ("Media views cannot be exported.").
    public var isExportable: Bool { kind != "mcp_media" }
}

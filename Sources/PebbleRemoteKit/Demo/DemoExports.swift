import Foundation
import PebbleProtocol

// Lane T (2026-10-31): the demo's exports and views' earlier revisions, shaped as exports.py and artifacts.py give
// them (read-only Pebble checkout: exports.py `preview`, `_render`, `checks`, `CHECK_LABELS`, `list`, `get`;
// artifacts.py `history`, `_retire`). The demo makes no file: it reports what Pebble would, and Save stays the Mac's.

struct DemoExports: Sendable {
    struct Plan: Sendable {
        var chat: String
        var format: String
        var viewID: String
        var revision: Int
        var title: String
        var kind: String
        var deadline: Date
    }

    /// Previews waiting for Create file, by plan id (used once).
    var plans: [String: Plan] = [:]
    /// Each conversation's export records, newest first.
    var records: [String: [JSONValue]] = [:]
    /// Plans whose Create file was cancelled while it worked.
    var cancelled: Set<String> = []
    /// Plans Create file is working on now, with their conversation.
    var rendering: [String: String] = [:]
    /// Views' earlier revisions, oldest first, once Stop added one (artifacts.py keeps every revision).
    var earlier: [String: [JSONValue]] = [:]
    private var seq = 0

    init(now: Date) {
        let at = now.timeIntervalSince1970 - 2 * 3600
        records[DemoData.commitsChat] = [
            Self.record(
                id: "x-demo-commits", chat: DemoData.commitsChat, format: "html", status: "verified",
                title: "Commits by author",
                viewID: "v-commits-table", revision: 1, at: at, checks: Self.checks(for: "html"),
                saves: [
                    [
                        "id": "s-demo-1", "state": "saved", "path": "/Users/you/Documents/Commits by author.html",
                        "sha256": .string(Self.digest("x-demo-commits")), "verified": true, "created": .double(at + 60),
                    ]
                ])
        ]
    }

    mutating func nextID(_ prefix: String) -> String {
        seq += 1
        return "\(prefix)-demo-\(seq)"
    }

    // MARK: Records (exports.py `_render`'s receipt)

    static func record(
        id: String, chat: String, format: String, status: String, title: String, viewID: String, revision: Int,
        at: Double,
        checks: [JSONValue], saves: [JSONValue] = [], reason: String? = nil
    ) -> JSONValue {
        let source: JSONValue = [
            "kind": "artifact", "id": .string(viewID), "revision": .int(revision), "digest": .string(digest(viewID)),
        ]
        var object: [String: JSONValue] = [
            "export_id": .string(id), "plan_id": .string("p-" + id), "chat_id": .string(chat),
            "format": .string(format),
            "status": .string(status), "title": .string(title), "source": source,
            "options": ["include_answers": false, "paper": "a4"], "file": .null, "checks": [], "failed_checks": [],
            "readback": .null, "notes": [], "reason": .null, "created": .double(at), "completed": .double(at + 2),
            "published": false, "authorization": "none", "saves": .array(saves),
        ]
        if let reason { object["reason"] = .string(reason) }
        if ["verified", "unverified"].contains(status) {
            let name = title.replacingOccurrences(of: "/", with: "-") + "." + format
            let bytes = format == "csv" ? 412 : 18_730
            let file: [String: JSONValue] = [
                "name": .string("export." + format), "suggested_name": .string(name), "bytes": .int(bytes),
                "sha256": .string(digest(id)),
            ]
            var readback: [String: JSONValue] = ["text_coverage": .double(1)]
            if format == "xlsx" || format == "csv" { readback["sheets"] = 1 }
            if format == "docx" { readback["pages"] = 1 }
            object["file"] = .object(file)
            object["readback"] = .object(readback)
            object["checks"] = .array(checks)
            object["failed_checks"] = .array(checks.filter { $0["passed"]?.bool != true }.compactMap { $0["name"] })
        }
        return .object(object)
    }

    /// The readback checks Pebble runs for a format (exports.py `checks`), as they pass on a clean file. A Word
    /// document can't be thumbnailed without Quick Look, so the demo's says so and is unverified, as Pebble's would be.
    static func checks(for format: String) -> [JSONValue] {
        func check(_ name: String, _ label: String, _ detail: String, passed: Bool = true) -> JSONValue {
            ["name": .string(name), "label": .string(label), "passed": .bool(passed), "detail": .string(detail)]
        }
        var list = [
            check("parsed", "The file opens and parses", "Parsed in the confined readback worker."),
            check("no_external_refs", "No external links, scripts or attachments", "None found."),
            check("text_coverage", "Text matches the source", "100.0% of the source words were found (98% needed)."),
        ]
        switch format {
        case "xlsx", "csv":
            list.append(check("sheet_count", "Every table has its sheet", "1 of 1 sheets."))
            list.append(check("cells_match", "Cells match source values and types", ""))
            list.append(
                check(
                    "formulas_neutralized", "Formula-like text is neutralized",
                    "No formula-like text is left unprotected."))
        case "docx":
            list.append(check("tables_preserved", "Tables keep their rows and columns", ""))
            list.append(check("no_macros", "No macros or embedded objects", "No macros."))
            list.append(
                check(
                    "thumbnail", "Quick Look shows content within the margins",
                    "Quick Look isn't available in the demo.",
                    passed: false))
        default:
            list.append(check("resanitized_equal", "Re-sanitizing gives the same bytes", ""))
            list.append(check("head_matches", "The page header is Pebble's fixed template", ""))
            list.append(check("csp", "The content policy blocks scripts and network", ""))
            list.append(check("no_scripts", "No scripts or event handlers", "None found."))
        }
        return list
    }

    /// A stable stand-in for a SHA-256 (64 hex characters) the demo never computes over a file.
    static func digest(_ seed: String) -> String {
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in seed.utf8 { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        var hex = String(value, radix: 16)
        while hex.count < 64 { hex += String(value &* 31, radix: 16) }
        return String(hex.prefix(64))
    }

    // MARK: Views' earlier revisions (artifacts.py `history`)

    /// Every revision of a view, oldest first: the ones kept before, then the current row. A seeded view that is
    /// already past its first revision gets an earlier one with less data (the table had one author fewer).
    func history(of row: JSONValue, in chat: String) -> [JSONValue] {
        guard let id = row["id"]?.string, let revision = row["revision"]?.int else { return [row] }
        var list = earlier[chat + "/" + id] ?? []
        if list.count < revision - 1 {
            for number in (list.count + 1)..<revision {
                list.append(Self.earlierCopy(of: row, revision: number))
            }
        }
        return Array(list.prefix(revision - 1)) + [row]
    }

    static func earlierCopy(of row: JSONValue, revision: Int) -> JSONValue {
        guard case .object(var object) = row else { return row }
        object["revision"] = .int(revision)
        object["status"] = "ready"
        object["updated"] = object["created"] ?? .null
        if object["kind"]?.string == "table", case .object(var data)? = object["data"], let rows = data["rows"]?.array,
            rows.count > 1
        {
            data["rows"] = .array(Array(rows.dropLast()))
            object["data"] = .object(data)
        }
        object["form_question"] = nil
        return .object(object)
    }
}

import Foundation

// Lane T (2026-10-31): a view's revisions, Stop and export. Pebble's words, word for word, from its canvas and export
// section (read-only Pebble checkout: src/components/ArtifactPanel.vue, NativeArtifactRenderer.vue, QuizRenderer.vue,
// DashboardRenderer.vue, ExportPanel.vue and App.vue's "Export a view"). Where the phone must differ (your Mac, not
// this Mac; a control the phone puts elsewhere; Pebble's word for a view), the comment beside the constant says why.
extension AppCopy {
    nonisolated public enum ViewHistory {
        // MARK: Revisions (CV-01, CV-02, CV-08)

        /// The canvas header while an earlier revision shows ("Earlier version 2").
        public static func earlierVersion(_ revision: Int) -> String { "Earlier version \(revision)" }
        public static let revision = "Revision"
        /// The revision choices (ArtifactPanel.vue's Choose artifact revision).
        public static func current(_ revision: Int) -> String { "Current \u{00B7} revision \(revision)" }
        public static func earlier(_ revision: Int, status: String?) -> String {
            "Revision \(revision) \u{00B7} \(status ?? "ready")"
        }
        /// What an earlier revision says (NativeArtifactRenderer.vue, QuizRenderer.vue, DashboardRenderer.vue); the
        /// views Pebble gives no note say only that the revision is an earlier one.
        public static func earlierNote(kind: String) -> String {
            switch kind {
            case "form": "Historical revision. Return to the current revision to answer."
            case "quiz": "Historical revision. Return to the current revision to take this quiz."
            case "dashboard": "Historical revision. Live data is shown as it was saved."
            default: "Historical revision."
            }
        }
        public static let more = "More"
        /// The canvas's "Export…", which opens this view's export.
        public static let export = "Export\u{2026}"

        // MARK: Stop (CV-09)

        /// Pebble's canvas says "Stop artifact" (its HTML view says "Stop view"); the phone calls Pebble's artifacts
        /// views everywhere, so it says "Stop view".
        public static let stop = "Stop view"
        /// Pebble stops at once; the phone asks first, because a stopped view can't be started again.
        public static let stopTitle = "Stop this view?"
        public static func stopMessage(waitingForm: Bool) -> String {
            waitingForm
                ? "Pebble keeps it as it is now and it stops asking: its question is cancelled, and a task that needs "
                    + "the answer stops. This can't be undone."
                : "Pebble keeps it as it is now, and it stops: a dashboard no longer refreshes and a quiz no longer "
                    + "takes answers. This can't be undone."
        }
    }

    nonisolated public enum Exports {
        // MARK: The export (DT-26 to DT-31)

        /// App.vue's heading in Details › Task.
        public static let title = "Export a view"
        public static let opensHint = "Chooses a view and a format, then makes a checked file on your Mac"
        /// Pebble's "Exports make a file on this Mac…": the phone says "your Mac".
        public static let note =
            "Exports make a file on your Mac and check it by reading it back. Nothing is shared, uploaded or sent."
        public static let view = "View"
        public static let format = "Format"
        /// ExportPanel.vue `FORMATS`.
        public static func formatName(_ id: String) -> String {
            switch id {
            case "html": "Web page (HTML, no scripts)"
            case "docx": "Word document (DOCX)"
            case "xlsx": "Excel workbook (XLSX)"
            case "csv": "CSV table"
            default: id.uppercased()
            }
        }
        public static let includeAnswers = "Include the answer key"
        public static let preview = "Preview export"
        public static let checking = "Checking\u{2026}"
        public static let previewReady = "Preview ready. Nothing is written until you choose Create file."
        public static let optionsChanged = "Options changed. Preview the export again."
        public static func viewChanged(_ revision: Int) -> String {
            "This view changed to revision \(revision). Preview the export again."
        }
        public static let thisSource = "This source"
        /// "HTML · revision 3 · about 2 page(s) · preview valid until 14:32"
        public static func planLine(format: String, revision: Int?, pages: Int?, until: String?) -> String {
            var line = format.uppercased()
            if let revision { line += " \u{00B7} revision \(revision)" }
            if let pages { line += " \u{00B7} about \(pages) page(s)" }
            if let until { line += " \u{00B7} preview valid until \(until)" }
            return line
        }
        public static let createFile = "Create file"
        public static let creating = "Creating and checking the file\u{2026}"
        public static let cancel = "Cancel"

        // MARK: The verdict

        /// ExportPanel.vue `STATUS`.
        public static func verdictNote(_ status: String) -> String {
            switch status {
            case "verified": "Verified: every readback check passed."
            case "unverified":
                "Unverified: the file was made, but some checks did not pass. You can still save it; it stays "
                    + "labelled unverified."
            case "unavailable": "Unavailable: nothing was written."
            case "cancelled": "Cancelled: the partial file was removed."
            case "discarded": "Pebble's copy was deleted."
            default: "Failed: nothing was written."
            }
        }
        /// "Verified · HTML"
        public static func verdict(_ status: String, format: String) -> String {
            "\(verdictWord(status)) \u{00B7} \(format.uppercased())"
        }
        public static func verdictWord(_ status: String) -> String {
            switch status {
            case "verified": "Verified"
            case "unverified": "Unverified"
            case "unavailable": "Unavailable"
            case "cancelled": "Cancelled"
            // The phone's word for a record whose file Pebble deleted (`discarded`), which the Mac's panel never lists.
            case "discarded": "Deleted"
            default: "Failed"
            }
        }
        /// "Commits by author.html · 18 KB · 1 sheet(s) · 100% of the source text found · revision 1 ·
        /// SHA-256 1a2b3c4d5e6f…"
        public static func fileLine(
            name: String?, bytes: Int?, sheets: Int?, pages: Int?, coverage: Double?, revision: Int?, sha256: String?
        ) -> String? {
            guard let sha256 else { return nil }
            var parts: [String] = [name ?? ""]
            if let bytes { parts.append(size(bytes)) }
            if let sheets { parts.append("\(sheets) sheet(s)") } else if let pages { parts.append("\(pages) page(s)") }
            if let coverage { parts.append("\(percent(coverage))% of the source text found") }
            if let revision { parts.append("revision \(revision)") }
            parts.append("SHA-256 \(sha256.prefix(12))\u{2026}")
            return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        }
        /// ExportPanel.vue `size`: MB from 1 MiB, else KB (at least 1).
        public static func size(_ bytes: Int) -> String {
            bytes >= 1 << 20
                ? String(format: "%.1f MB", Double(bytes) / Double(1 << 20))
                : "\(max(1, Int((Double(bytes) / 1024).rounded()))) KB"
        }
        /// Pebble floors the coverage to a tenth of a percent: 0.9987 is "99.8".
        static func percent(_ coverage: Double) -> String {
            let tenths = (coverage * 1000).rounded(.down) / 10
            return tenths.rounded() == tenths ? String(Int(tenths)) : String(tenths)
        }
        public static let checks = "Readback checks"
        /// "Passed: Text matches the source — 100.0% of the source words were found (98% needed)."
        public static func check(passed: Bool, label: String, detail: String) -> String {
            (passed ? "Passed: " : "Did not pass: ") + label + (detail.isEmpty ? "" : " \u{2014} \(detail)")
        }

        // MARK: Pebble's copy, and saving (DT-30, DT-31)

        public static let deleteCopy = "Delete Pebble's copy"
        public static let deleted = "Pebble's copy was deleted. Files you saved elsewhere are unchanged."
        /// Pebble deletes at once; the phone asks first, because the file can't be brought back.
        public static let deleteTitle = "Delete Pebble's copy?"
        public static let deleteMessage =
            "Pebble deletes the file it made on your Mac. Copies you saved elsewhere stay. This can't be undone."
        /// Save opens the Mac's Save dialog (ExportPanel.vue "Save to…"); the phone shows it as an "On your Mac" row.
        public static func saveOnMac(verified: Bool) -> String {
            verified ? "Save to\u{2026}" : "Save unverified file to\u{2026}"
        }
        public static let saveOnMacNote =
            "Saving opens a Save dialog on your Mac, so Pebble saves the file there. This iPhone can't receive the "
            + "file yet."

        // MARK: Earlier files (export_list, export_get; no button on the Mac, "/exports" lists them)

        public static let earlierFiles = "Earlier files"
        public static let noEarlierFiles = "No exports in this conversation yet."
        /// "HTML · Verified · 31 Oct 2026 at 14:02"
        public static func recordLine(format: String, status: String, created: String?) -> String {
            [format.uppercased(), verdictWord(status), created].compactMap { $0 }.joined(separator: " \u{00B7} ")
        }
        public static func savedTo(_ path: String) -> String { "Saved to \(path)" }
        /// "Verified copy · SHA-256 1a2b3c4d5e6f… · not published"
        public static func savedCopy(verified: Bool, sha256: String) -> String {
            let copy = verified ? "Verified copy" : "Unverified copy"
            return "\(copy) \u{00B7} SHA-256 \(sha256.prefix(12))\u{2026} \u{00B7} not published"
        }
        public static let saves = "Saved copies"
    }
}

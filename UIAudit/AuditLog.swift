import Foundation
import XCTest

/// What the audit noticed while it drove the app: findings (a control that couldn't be found or tapped, a tap that
/// changed nothing, a crash, a harness problem) and the accessibility audit's issues, each tied to the screenshot taken
/// at the time. Written into the result bundle as JSON attachments at the end of every area, so a crash in one area
/// keeps the others' records. Locked, because XCTest may report an issue from any thread.
final class AuditLog: @unchecked Sendable {
    struct Finding: Codable, Sendable {
        /// The last screenshot taken before it, by its number (`NNN-…`); 0 before the first.
        var shot: Int
        var area: String
        var screen: String
        var kind: String
        var detail: String
    }

    struct Issue: Codable, Sendable {
        var shot: String
        var area: String
        var screen: String
        var type: String
        var compact: String
        var detailed: String
        var element: String?
    }

    private let lock = NSLock()
    private var findings: [Finding] = []
    private var issues: [Issue] = []
    private var currentArea = "start"

    /// The area running now, for issues XCTest reports outside the tour's own notes.
    var area: String {
        get { lock.withLock { currentArea } }
        set { lock.withLock { currentArea = newValue } }
    }

    func add(_ finding: Finding) {
        lock.withLock { findings.append(finding) }
    }

    func add(_ issue: Issue) {
        lock.withLock { issues.append(issue) }
    }

    /// The area's records as two JSON attachments, kept even when the run passes.
    func attachments(for area: String) -> [XCTAttachment] {
        let (areaFindings, areaIssues) = lock.withLock {
            (findings.filter { $0.area == area }, issues.filter { $0.area == area })
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var made: [XCTAttachment] = []
        for (name, data) in [
            ("findings-\(area).json", try? encoder.encode(areaFindings)),
            ("accessibility-\(area).json", try? encoder.encode(areaIssues)),
        ] {
            guard let data else { continue }
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = name
            attachment.lifetime = .keepAlways
            made.append(attachment)
        }
        return made
    }
}

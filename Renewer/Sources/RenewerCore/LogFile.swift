import Foundation

/// `~/Library/Logs/PebbleRemoteRenewer.log`: one line per event, every line redacted first, owner-only (0600). When it
/// passes the limit it becomes `PebbleRemoteRenewer.log.1` (the one before that is dropped), so the two stay under
/// 2 MB together. Writes happen in order on a private queue, so any thread may log.
public final class FileLog: Sendable {
    public let url: URL
    public let limit: Int
    private let queue = DispatchQueue(label: "io.github.tohin003.PebbleRemoteRenewer.log")

    public init(url: URL, limit: Int = 1_000_000) {
        self.url = url
        self.limit = limit
    }

    public func write(_ message: String, at date: Date = Date()) {
        let line = LogLine.format(Redactor.redact(message), at: date)
        let url = self.url
        let limit = self.limit
        queue.async { FileLog.append(line, to: url, limit: limit) }
    }

    /// Writes before returning (for the last line before the process exits).
    public func writeNow(_ message: String, at date: Date = Date()) {
        let line = LogLine.format(Redactor.redact(message), at: date)
        let url = self.url
        let limit = self.limit
        queue.sync { FileLog.append(line, to: url, limit: limit) }
    }

    /// Waits for the lines already written.
    public func flush() {
        queue.sync {}
    }

    static func append(_ line: String, to url: URL, limit: Int) {
        let manager = FileManager.default
        let path = url.path(percentEncoded: false)
        let size = ((try? manager.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? 0
        if LogLine.needsRotation(size: size, adding: line.utf8.count, limit: limit) {
            let older = url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".1")
            try? manager.removeItem(at: older)
            try? manager.moveItem(at: url, to: older)
        }
        if !manager.fileExists(atPath: path) {
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = manager.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}

public enum LogLine {
    /// "2026-11-05 03:12:00 +0530 message", one line however many lines the message had.
    public static func format(_ message: String, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let flat = message.split(whereSeparator: \.isNewline).joined(separator: " | ")
        return "\(formatter.string(from: date)) \(flat)\n"
    }

    public static func needsRotation(size: Int, adding: Int, limit: Int) -> Bool {
        size > 0 && size + adding > limit
    }
}

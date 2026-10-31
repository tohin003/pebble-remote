import Foundation
import PebbleDesign
import PebbleRemoteKit
import UniformTypeIdentifiers

/// A file chosen in the Files app, read for attaching: its bytes and name (at most Pebble's 50 MB), and a small preview
/// when it is an image. Read off the main thread.
nonisolated struct PickedFile: Sendable {
    let data: Data
    let name: String
    let preview: Data?

    /// Pebble's limit for one file (src/bridge.ts).
    static let maxBytes = 50_000_000

    /// Reads the file the system's picker returned (a security-scoped address). Throws the words to show when it is
    /// too large or can't be read.
    static func read(_ url: URL) throws -> PickedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let size = values?.fileSize, size > maxBytes { throw PersonFacingError(message: StoreWords.fileTooLarge) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw PersonFacingError(message: AppCopy.AddContext.unreadableFile)
        }
        guard data.count <= maxBytes else { throw PersonFacingError(message: StoreWords.fileTooLarge) }
        let isImage = values?.contentType?.conforms(to: .image) ?? false
        let preview = isImage ? PhotoPayload(imageData: data, maxPixels: PhotoPayload.previewPixels)?.data : nil
        return PickedFile(data: data, name: url.lastPathComponent, preview: preview)
    }
}

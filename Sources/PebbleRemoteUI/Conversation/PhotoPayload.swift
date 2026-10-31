import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo from the phone, ready to attach to a conversation: a JPEG with the photo's orientation applied and its long
/// side at most 2,560 px, whatever the library held (HEIC, PNG, a large original). The Mac reads JPEG everywhere.
/// Usable off the main thread (a file from Files is read there).
nonisolated struct PhotoPayload: Sendable, Equatable {
    let data: Data
    let filename: String
    let mimeType: String

    static let maxPixels = 2560
    /// The long side of a preview the phone keeps while a photo waits in a new conversation.
    static let previewPixels = 160

    /// Nil when the data isn't an image ImageIO can read.
    init?(imageData: Data, name: String = "Photo", maxPixels: Int = Self.maxPixels) {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, quality as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        data = output as Data
        filename = "\(name).jpg"
        mimeType = UTType.jpeg.preferredMIMEType ?? "image/jpeg"
    }

    /// A small JPEG of the photo, for the chip that shows it waiting.
    var preview: Data? {
        PhotoPayload(imageData: data, maxPixels: Self.previewPixels)?.data
    }
}

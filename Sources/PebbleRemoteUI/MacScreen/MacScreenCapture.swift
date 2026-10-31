import CoreGraphics
import Foundation
import ImageIO
import PebbleRemoteKit

/// A screenshot of the Mac's displays (claude-w's C3, `remote.screenshot`), decoded for the screen. It lives only in
/// memory while the Mac screen view is open: nothing is written to the phone unless the person shares it.
struct MacScreenCapture: Sendable {
    struct Display: Identifiable, Sendable {
        /// The Mac's own display index (what `remote.screenshot {display:}` takes).
        let index: Int
        let image: CGImage
        var id: Int { index }
        var width: Int { image.width }
        var height: Int { image.height }
    }

    let takenAt: Date
    let displays: [Display]

    /// Decodes each display's JPEG; a display whose data can't be read is left out.
    init(takenAt: Date, jpegs: [(index: Int, data: Data)]) {
        self.takenAt = takenAt
        displays = jpegs.compactMap { item in
            Self.decode(item.data).map { Display(index: item.index, image: $0) }
        }
    }

    /// The store's screenshot, decoded; the Mac's clock when it said, else now.
    init(_ screenshot: MacScreenshot) {
        self.init(
            takenAt: screenshot.takenAt ?? .now,
            jpegs: screenshot.displays.map { (index: $0.index, data: $0.data) })
    }

    /// The longest side a display's picture may have, in pixels. C3 caps it at 2,560; this leaves room for a bridge
    /// that rounds differently, and keeps one decoded display under 64 MB.
    static let maximumSide = 4096

    /// The picture, or nil when it is not an image or claims more than `maximumSide` pixels on a side. The size is
    /// read from the image's header before anything is decoded: a JPEG of a few KB can claim 10,000 by 10,000 pixels,
    /// which ImageIO accepts and which takes 400 MB to draw, per display (security review 2026-10-30, S-11).
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            (1...maximumSide).contains(width), (1...maximumSide).contains(height)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

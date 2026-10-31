import CoreGraphics
import Foundation
import ImageIO
import PebbleRemoteKit
import Testing
import UniformTypeIdentifiers

@testable import PebbleRemoteUI

/// Photos the person attaches, and the Mac's screenshots: decoded and re-encoded with ImageIO, nothing kept.
struct ImageTests {
    /// A plain image in the given format, made in memory.
    private func image(width: Int, height: Int, as type: UTType) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.31, green: 0.43, blue: 0.33, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let picture = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, picture, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func aLargePhotoBecomesAJPEGNoLongerThan2560Pixels() throws {
        let payload = try #require(PhotoPayload(imageData: try image(width: 4000, height: 3000, as: .png)))
        #expect(payload.mimeType == "image/jpeg")
        #expect(payload.filename == "Photo.jpg")
        let decoded = try #require(MacScreenCapture.decode(payload.data))
        #expect(max(decoded.width, decoded.height) <= PhotoPayload.maxPixels)
        #expect(decoded.width > decoded.height)
    }

    @Test func dataThatIsNoImageIsRefused() {
        #expect(PhotoPayload(imageData: Data("not an image".utf8)) == nil)
    }

    @Test func aScreenshotKeepsTheDisplaysItCanRead() throws {
        let jpeg = try image(width: 320, height: 200, as: .jpeg)
        let screenshot = MacScreenshot(
            takenAt: Date(timeIntervalSince1970: 1_800_000_000),
            displays: [
                .init(index: 0, width: 320, height: 200, format: "jpeg", data: jpeg),
                .init(index: 1, width: 10, height: 10, format: "jpeg", data: Data("broken".utf8)),
            ])
        let capture = MacScreenCapture(screenshot)
        #expect(capture.displays.map(\.index) == [0])
        #expect(capture.displays.first?.width == 320)
        #expect(capture.takenAt == Date(timeIntervalSince1970: 1_800_000_000))
    }
}

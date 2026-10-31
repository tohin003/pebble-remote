import CoreGraphics
import Foundation
import ImageIO
import LocalAuthentication
import PebbleDesign
import PebbleRemoteKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import PebbleRemoteUI

// The security review of 2026-10-30 (docs/reviews/security-2026-10-30.md): the tests that hold its fixes in the
// screens in place, named after the findings (S-xx).

struct SecurityReviewUITests {
    // MARK: S-03: links inside the app

    @Test(arguments: ["https://example.com/docs", "HTTPS://Example.com", "http://192.168.1.20:8080/x"])
    func webLinksOpenInTheBrowser(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(InAppLinks.opensInBrowser(url))
    }

    @Test(arguments: [
        "pebble-remote://pair?v=1&bid=b1&name=Studio&pin=p&code=c&ep=10.0.0.9%3A47800",
        "pebble-remote://chat/c1", "pebble-remote://reviews", "shortcuts://run-shortcut?name=Wipe",
        "tel:+15555550100", "sms:+15555550100", "facetime:someone", "mailto:a@example.com", "file:///etc/passwd",
        "javascript:alert(1)", "https:no-host", "x-apple-reminderkit://REMCDReminder/1",
    ])
    func everyOtherLinkInAReplyStaysPut(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(!InAppLinks.opensInBrowser(url), "\(text) should not leave the app")
    }

    // MARK: S-04: what the pairing confirmation says

    private static let paired = PairedMac(
        bridgeID: "b1", name: "Studio Mac", deviceID: "d1", pin: "8dWUSbcnFl3nMr8oMzgSK5liimFZGP7cZ9h4__z0fac",
        endpoints: [Endpoint(host: "192.168.1.20", port: 47800)], pairedAt: Date(timeIntervalSince1970: 1_800_000_000))

    private static func link(bridgeID: String, pin: String) -> PairingLink {
        PairingLink(
            version: 1, bridgeID: bridgeID, macName: "Studio Mac", pin: pin, code: "c",
            endpoints: [Endpoint(host: "203.0.113.9", port: 443)])
    }

    @Test func aLinkWithThePairedMacsIDButAnotherKeyWarnsBeforePairing() {
        let spoof = Self.link(bridgeID: "b1", pin: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let warning = PairingConfirmSheet.warning(for: spoof.relation(to: Self.paired))
        #expect(warning == AppCopy.Pairing.confirmNewKey("Studio Mac"))
        #expect(warning?.contains("Studio Mac") == true)
    }

    @Test func otherLinksWarnAsBefore() {
        #expect(PairingConfirmSheet.warning(for: Self.link(bridgeID: "b2", pin: "x").relation(to: Self.paired))
            == AppCopy.Pairing.confirmReplaces("Studio Mac"))
        #expect(PairingConfirmSheet.warning(for: Self.link(bridgeID: "b1", pin: Self.paired.pin).relation(to: Self.paired))
            == nil)
        #expect(PairingConfirmSheet.warning(for: Self.link(bridgeID: "b1", pin: "x").relation(to: nil)) == nil)
    }

    // MARK: S-09: the app lock fails closed

    @Test func onlyAPhoneWithoutAPasscodeLiftsTheLockUnchecked() {
        func error(_ code: LAError.Code) -> NSError { NSError(domain: LAErrorDomain, code: code.rawValue) }
        #expect(AppLock.outcomeWhenUnavailable(error(.passcodeNotSet)) == .unavailable)
        for code in [LAError.Code.biometryLockout, .biometryNotAvailable, .notInteractive, .invalidContext] {
            #expect(AppLock.outcomeWhenUnavailable(error(code)) == .failed, "\(code)")
        }
        #expect(AppLock.outcomeWhenUnavailable(nil) == .failed)
        #expect(AppLock.outcomeWhenUnavailable(NSError(domain: "other", code: LAError.Code.passcodeNotSet.rawValue)) == .failed)
    }

    // MARK: S-11: a screenshot that claims too many pixels

    private func jpeg(width: Int, height: Int) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.31, green: 0.43, blue: 0.33, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let picture = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, picture, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// The same JPEG with its frame header (SOF0 or SOF2) claiming another size.
    private func claiming(width: Int, height: Int, in jpeg: Data) throws -> Data {
        var bytes = [UInt8](jpeg)
        let start = try #require(
            bytes.indices.dropLast(9).first { bytes[$0] == 0xFF && (bytes[$0 + 1] == 0xC0 || bytes[$0 + 1] == 0xC2) })
        bytes[start + 5] = UInt8(height >> 8)
        bytes[start + 6] = UInt8(height & 0xFF)
        bytes[start + 7] = UInt8(width >> 8)
        bytes[start + 8] = UInt8(width & 0xFF)
        return Data(bytes)
    }

    @Test func aScreenshotClaimingTooManyPixelsIsNotDecoded() throws {
        let small = try jpeg(width: 64, height: 40)
        #expect(MacScreenCapture.decode(small)?.width == 64)
        // Unguarded, ImageIO hands back a picture 10,000 pixels square for a few KB (400 MB once drawn); it refuses
        // only from about 16,000 pixels on.
        let bomb = try claiming(width: 10_000, height: 10_000, in: small)
        let source = try #require(CGImageSourceCreateWithData(bomb as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width == 10_000)
        #expect(MacScreenCapture.decode(bomb) == nil)
        #expect(MacScreenCapture.decode(try claiming(width: 60_000, height: 60_000, in: small)) == nil)
        #expect(MacScreenCapture.decode(try claiming(width: MacScreenCapture.maximumSide + 1, height: 40, in: small)) == nil)
        let screenshot = MacScreenshot(
            takenAt: nil,
            displays: [
                .init(index: 0, width: 64, height: 40, format: "jpeg", data: small),
                .init(index: 1, width: 10_000, height: 10_000, format: "jpeg", data: bomb),
            ])
        #expect(MacScreenCapture(screenshot).displays.map(\.index) == [0])
    }
}

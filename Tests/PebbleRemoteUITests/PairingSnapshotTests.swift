import Foundation
import PebbleDesign
import PebbleRemoteKit
import SwiftUI
import Testing

@testable import PebbleRemoteUI

#if canImport(AppKit)
import AppKit

/// Renders the pairing code screen to PNG files for a person (or an agent) to look at, at an iPhone's width and at the
/// narrowest one. Off unless `PEBBLE_DESIGN_SNAPSHOTS` names a folder, like PebbleDesign's own snapshots:
///
///     PEBBLE_DESIGN_SNAPSHOTS=/private/tmp/x scripts/swift.sh test --filter PairingSnapshotTests
///
/// These render with macOS's SwiftUI, so system controls look like the Mac's (the spinner shows as a placeholder) and
/// Dynamic Type does not apply; Pebble's own drawing (the avatar, the card, colours, type) is the same on both.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PEBBLE_DESIGN_SNAPSHOTS"] != nil))
struct PairingSnapshotTests {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PEBBLE_DESIGN_SNAPSHOTS"] ?? "/dev/null")

    func save<V: View>(_ name: String, dark: Bool, width: CGFloat = 393, @ViewBuilder _ view: () -> V) throws {
        let content = view()
            .frame(width: width)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(PebbleColor.fixed(.bg, dark: dark))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw SnapshotError.noImage(name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name + (dark ? "-dark" : "") + ".png"))
    }

    enum SnapshotError: Error { case noImage(String) }

    @Test func theCodeScreen() throws {
        let code = try #require(PairingCode(digits: "035072"))
        for dark in [false, true] {
            try save("pairing-code", dark: dark) {
                PairingCodePanel(code: code, cancel: {}).padding()
            }
        }
        try save("pairing-code-320", dark: false, width: 320) {  // an iPhone SE
            PairingCodePanel(code: code, cancel: {}).padding()
        }
    }

    @Test func theWordsWhenThePairingWasNotConfirmed() throws {
        for dark in [false, true] {
            try save("pairing-not-confirmed", dark: dark) {
                VStack {
                    PairingHeader()
                    Label(AppCopy.Pairing.notConfirmed, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(PebbleColor.danger)
                        .multilineTextAlignment(.leading)
                }
                .padding()
            }
        }
    }
}
#endif

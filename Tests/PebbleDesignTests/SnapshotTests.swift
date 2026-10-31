import Foundation
import PebbleProtocol
import SwiftUI
import Testing

@testable import PebbleDesign

#if canImport(AppKit)
import AppKit

/// Renders components to PNG files for a person (or an agent) to look at. Off unless `PEBBLE_DESIGN_SNAPSHOTS` names
/// a folder: `PEBBLE_DESIGN_SNAPSHOTS=/private/tmp/x scripts/swift.sh test --filter SnapshotTests`. These render
/// with macOS's SwiftUI, so system controls look like the Mac's; Pebble's own drawing (the avatar, colours, cards)
/// is the same on both.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PEBBLE_DESIGN_SNAPSHOTS"] != nil))
struct SnapshotTests {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PEBBLE_DESIGN_SNAPSHOTS"] ?? "/dev/null")

    func save<V: View>(_ name: String, dark: Bool = false, scale: CGFloat = 2, @ViewBuilder _ view: () -> V) throws {
        let content = view()
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(dark ? PebbleColor.fixed(.bg, dark: true) : PebbleColor.fixed(.bg, dark: false))
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw SnapshotError.noImage(name) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.noImage(name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name + (dark ? "-dark" : "") + ".png"))
    }

    enum SnapshotError: Error { case noImage(String) }

    @Test func avatarPoses() throws {
        for dark in [false, true] {
            try save("avatar-poses", dark: dark) {
                let poses = PebbleAvatar.Pose.allCases
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<((poses.count + 4) / 5), id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(poses[(row * 5)..<min(poses.count, row * 5 + 5)], id: \.self) { pose in
                                VStack(spacing: 2) {
                                    PebbleAvatar(pose: pose, animated: false).frame(width: 110, height: 110)
                                    Text(pose.rawValue).font(.caption).foregroundStyle(PebbleColor.secondaryText)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    @Test func components() throws {
        for dark in [false, true] {
            try save("components", dark: dark) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        StatusPill(status: .editing, since: .now.addingTimeInterval(-125))
                        StatusPill(status: .review)
                        StatusPill(status: .error)
                        StatusPill(status: .paused)
                    }
                    HStack {
                        RouteBadge(route: .tailscale, roundTripMilliseconds: 41)
                        ModeChip(mode: .ask)
                        ModeChip(mode: .full)
                    }
                    ActivityLine(text: "Edited src/auth/login.ts", status: .editing)
                    ActivityLine(text: "Ran npm test", status: .testing)
                    ReviewCardView(
                        kind: .command, title: ReviewCopy.leadCommand(writable: false), detail: "npm test",
                        conversation: "Tidy the test suite", created: nil, isBusy: false, onApprove: {}, onReject: {})
                    MessageBubble(role: .person, text: "Can you fix the login test? It fails on **CI** only.")
                    MessageBubble(
                        role: .pebble,
                        text: "## What I found\nThe test reads `TZ` from the machine.\n\n1. Pin the zone.\n2. Run it again.\n\n```ts\nprocess.env.TZ = \"UTC\";\n```",
                        isStreaming: true)
                    UnlockPrompt(remainingMinutes: nil) {}
                    RunBar(status: .testing, title: "Fix login", startedAt: .now.addingTimeInterval(-65), isPaused: false, onStop: {}, onPauseToggle: {})
                }
                .padding(16)
                .frame(width: 390)
            }
        }
    }

    @Test func avatarVeil() throws {
        for dark in [false, true] {
            try save("avatar-veil", dark: dark) {
                HStack(spacing: 16) {
                    PebbleAvatar(pose: .idle, stealth: false, animated: false).frame(width: 148, height: 148)
                    PebbleAvatar(pose: .idle, stealth: true, animated: false).frame(width: 148, height: 148)
                    PebbleAvatar(pose: .thinking, stealth: true, animated: false).frame(width: 48, height: 48)
                    PebbleAvatar(pose: .idle, stealth: true, animated: false).frame(width: 28, height: 28)
                    PebbleShape().fill(PebbleColor.accent).frame(width: 40, height: 40)
                }
                .padding(12)
            }
        }
    }
}
#endif

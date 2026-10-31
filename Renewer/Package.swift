// swift-tools-version: 6.2
// Pebble Remote Renewer: a Mac menu-bar item that shows how long the iPhone app's free 7-day signing has left and
// renews it through ../scripts/renew.sh. Its own package: the iOS package (../Package.swift), the app target and
// UIAudit never see it. Build and test it with ../scripts/swift.sh (serialized, nice 19, two jobs), outside a HOLD:
//   scripts/swift.sh test --package-path Renewer
//   scripts/swift.sh build --package-path Renewer -c release --product PebbleRemoteRenewer
// Then Renewer/install.sh puts it in place. See Renewer/README.md.
import PackageDescription

let package = Package(
    name: "PebbleRemoteRenewer",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PebbleRemoteRenewer", targets: ["PebbleRemoteRenewer"]),
    ],
    targets: [
        // Everything that decides or parses, as plain values: days left, the decision to renew, devicectl's device
        // list, renew.sh's output and exit codes, the state file, profiles' dates, the log's redaction. No UI.
        .target(name: "RenewerCore"),
        // The menu-bar app (SwiftUI MenuBarExtra, LSUIElement): scheduling, subprocesses, notifications.
        .executableTarget(name: "PebbleRemoteRenewer", dependencies: ["RenewerCore"]),
        .testTarget(name: "RenewerCoreTests", dependencies: ["RenewerCore"]),
    ],
    swiftLanguageModes: [.v6]
)

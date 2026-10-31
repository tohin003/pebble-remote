// swift-tools-version: 6.2
// Pebble Remote: the iPhone remote for Pebble. The Xcode app target (App/) is a thin shell over these modules.
// Build and test with scripts/swift.sh (serialized, low priority, works with Command Line Tools alone).
import PackageDescription

let ui: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "PebbleRemoteKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PebbleProtocol", targets: ["PebbleProtocol"]),
        .library(name: "PebbleRemoteKit", targets: ["PebbleRemoteKit"]),
        .library(name: "PebbleDesign", targets: ["PebbleDesign"]),
        .library(name: "PebbleRemoteUI", targets: ["PebbleRemoteUI"]),
    ],
    targets: [
        // The wire contract (the bridge contract) and Pebble's own vocabulary. Foundation only.
        .target(name: "PebbleProtocol"),
        // Transport, security, the observable store the screens read, and the in-app demo.
        .target(name: "PebbleRemoteKit", dependencies: ["PebbleProtocol"]),
        // Pebble's design language on iOS: tokens, copy, components, the avatar.
        .target(name: "PebbleDesign", dependencies: ["PebbleProtocol"], swiftSettings: ui),
        // Every screen. The app target only hosts PebbleRemoteRoot.
        .target(name: "PebbleRemoteUI", dependencies: ["PebbleRemoteKit", "PebbleDesign"], swiftSettings: ui),
        .testTarget(name: "PebbleProtocolTests", dependencies: ["PebbleProtocol"]),
        .testTarget(name: "PebbleRemoteKitTests", dependencies: ["PebbleRemoteKit"]),
        .testTarget(name: "PebbleDesignTests", dependencies: ["PebbleDesign"], swiftSettings: ui),
        // Lane E's tests (deep links, router, lock). On since 00:59 (lane E's "UI green"): every lane's test run now
        // compiles the screens, so lane E keeps PebbleRemoteUI compiling at every step.
        .testTarget(name: "PebbleRemoteUITests", dependencies: ["PebbleRemoteUI"], swiftSettings: ui),
    ],
    swiftLanguageModes: [.v6]
)

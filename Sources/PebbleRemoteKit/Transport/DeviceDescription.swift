import Foundation
import PebbleProtocol

/// What the phone tells the Mac about itself when pairing (`pair.device`, contract 3.2) and in every `hello` (`app`).
public struct DeviceDescription: Sendable, Hashable {
    /// The model identifier, "iPhone18,3".
    public var model: String
    /// "iOS 26.1"
    public var os: String
    /// The app's version and build, "1.0 (1)".
    public var app: String

    public init(model: String, os: String, app: String) {
        self.model = model
        self.os = os
        self.app = app
    }

    /// This device and app.
    public static var current: DeviceDescription {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
            let platform = "iOS"
        #else
            let platform = "macOS"
        #endif
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        // The simulator's uname is the Mac's ("arm64"); it names the simulated model in its environment.
        let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
        return DeviceDescription(
            model: simulated ?? (machine.isEmpty ? "unknown" : machine),
            os: "\(platform) \(version.majorVersion).\(version.minorVersion)\(patch)",
            app: "\(short) (\(build))")
    }

    /// The `pair` frame's `device` object.
    public func pairDevice(named name: String) -> PairFrame.Device {
        PairFrame.Device(name: name, model: model, os: os, app: app)
    }
}

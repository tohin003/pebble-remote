import Foundation
import Testing

@testable import PebbleDesign

#if canImport(AppKit)
import AppKit
#endif

/// Every SF Symbol PebbleDesign names exists, and existed by iOS 26.0 (the app's deployment target).
struct SymbolTests {
    /// Symbols the components use directly, beyond `PebbleSymbol`.
    static let direct = ["checkmark.circle.fill", "circle"]

    static var names: [String] { Array(Set(PebbleSymbol.all + direct)).sorted() }

    #if canImport(AppKit)
    @Test func everySymbolExistsOnThisMac() {
        let missing = Self.names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "\(missing)")
    }
    #endif

    /// The system's own symbol list says which release each name arrived in.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: symbolAvailabilityPath)))
    func everySymbolIsAvailableOnIOS26() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: symbolAvailabilityPath))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let symbols = try #require(plist["symbols"] as? [String: String])
        let releases = try #require(plist["year_to_release"] as? [String: [String: String]])
        var problems: [String] = []
        for name in Self.names {
            guard let year = symbols[name] else {
                problems.append("\(name): not in the list")
                continue
            }
            let ios = releases[year]?["iOS"] ?? "99"
            let parts = ios.split(separator: ".").compactMap { Int($0) }
            let major = parts.first ?? 99, minor = parts.count > 1 ? parts[1] : 0
            if major > 26 || (major == 26 && minor > 0) { problems.append("\(name): iOS \(ios)") }
        }
        #expect(problems.isEmpty, "\(problems)")
    }
}

/// The system's list of SF Symbols with the release each arrived in.
nonisolated let symbolAvailabilityPath = "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist"

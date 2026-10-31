import Foundation
@testable import RenewerCore

/// Fixed time zone, region and dates, so the words come out the same on any Mac.
enum Fixture {
    static let zone = TimeZone(identifier: "Asia/Kolkata")!
    static let locale = Locale(identifier: "en_GB")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        return calendar
    }

    static func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    /// The profile on the iPhone on 31 Oct: made 29 Oct 20:37:30 UTC, ends 5 Nov 20:37:30 UTC, which is
    /// Fri 6 Nov 02:07 on this Mac.
    static let expires = date("2026-11-05T20:37:30Z")
    /// Sat 31 Oct, 09:14 on this Mac.
    static let saturday = date("2026-10-31T03:44:00Z")
    /// Thu 5 Nov, 09:14 on this Mac: inside the last day.
    static let thursday = date("2026-11-05T03:44:00Z")

    static let bundleId = "io.github.tohin003.PebbleRemote"

    static func iPhone(
        _ identifier: String = "1A2B3C4D-1111-2222-3333-444455556666", udid: String? = "00008150-0000000000000000",
        tunnel: String = "disconnected", transport: String? = "wired"
    ) -> PairedDevice {
        PairedDevice(
            identifier: identifier, name: "iPhone", udid: udid, platform: "iOS", deviceType: "iPhone",
            pairingState: "paired", tunnelState: tunnel, transportType: transport)
    }
}

import Foundation
import Testing

@testable import PebbleRemoteKit

// Lane B: reading embedded.mobileprovision. The fixture is synthetic: a property list wrapped in bytes standing in for
// the CMS envelope (binary before and after, as in a real file).
@Suite("Lane B: provisioning profile")
struct ProvisioningProfileTests {
    static func blob(created: Date, expires: Date, team: String = "Sam Doe (Personal Team)", allDevices: Bool = false)
        -> Data
    {
        let plist: [String: Any] = [
            "AppIDName": "XC com example PebbleRemote",
            "CreationDate": created,
            "ExpirationDate": expires,
            "Name": "iOS Team Provisioning Profile: com.example.PebbleRemote",
            "TeamName": team,
            "TeamIdentifier": ["ABCDE12345"],
            "UUID": "2C8F1A44-0000-4000-8000-000000000000",
            "ProvisionedDevices": ["00008150-000A1B2C3D4E5F60"],
            "ProvisionsAllDevices": allDevices,
            "Entitlements": ["get-task-allow": true, "application-identifier": "ABCDE12345.com.example.PebbleRemote"],
        ]
        let xml = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        // A DER-ish header and a signature-ish tail, with bytes that are not UTF-8.
        let head = Data([0x30, 0x80, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02, 0xa0, 0x80, 0xff])
        let tail = Data([0x00, 0x00, 0xa0, 0x82, 0x0b, 0x3c, 0xfe, 0xed, 0x00, 0x00])
        return head + xml + tail
    }

    @Test func readsAFreeSevenDayProfile() throws {
        let created = Date(timeIntervalSince1970: 1_761_700_000)
        let expires = created.addingTimeInterval(7 * 86_400)
        let profile = try ProvisioningProfile(data: Self.blob(created: created, expires: expires))
        #expect(profile.expirationDate == expires)
        #expect(profile.creationDate == created)
        #expect(profile.teamName == "Sam Doe (Personal Team)")
        #expect(profile.teamIdentifier == "ABCDE12345")
        #expect(profile.name == "iOS Team Provisioning Profile: com.example.PebbleRemote")
        #expect(profile.allowsDebugging)
        #expect(profile.provisionedDeviceCount == 1)
        #expect(profile.looksLikeFreeProfile)
        #expect(profile.lifespan == TimeInterval(7 * 86_400))
    }

    @Test func countsWholeDaysLeft() throws {
        let created = Date(timeIntervalSince1970: 1_761_700_000)
        let expires = created.addingTimeInterval(7 * 86_400)
        let profile = try ProvisioningProfile(data: Self.blob(created: created, expires: expires))
        #expect(profile.daysLeft(at: created) == 7)
        #expect(profile.daysLeft(at: created.addingTimeInterval(3600)) == 6)  // 6 days 23 hours
        #expect(profile.daysLeft(at: expires.addingTimeInterval(-3600)) == 0)
        #expect(!profile.isExpired(at: expires.addingTimeInterval(-1)))
        #expect(profile.isExpired(at: expires))
        #expect(profile.daysLeft(at: expires.addingTimeInterval(86_400)) == 0)
        #expect(profile.timeLeft(at: expires.addingTimeInterval(5)) == 0)
    }

    @Test func aYearLongProfileIsNotFree() throws {
        let created = Date(timeIntervalSince1970: 1_761_700_000)
        let paid = try ProvisioningProfile(
            data: Self.blob(created: created, expires: created.addingTimeInterval(365 * 86_400), team: "Example Ltd"))
        #expect(!paid.looksLikeFreeProfile)
        let enterprise = try ProvisioningProfile(
            data: Self.blob(created: created, expires: created.addingTimeInterval(5 * 86_400), allDevices: true))
        #expect(!enterprise.looksLikeFreeProfile)
    }

    @Test func refusesWhatIsNotAProfile() {
        #expect(throws: ProvisioningProfile.ReadError.noPropertyList) {
            try ProvisioningProfile(data: Data([0x30, 0x80, 0x01, 0x02]))
        }
        let other = try! PropertyListSerialization.data(fromPropertyList: ["Name": "x"], format: .xml, options: 0)
        #expect(throws: ProvisioningProfile.ReadError.notAProfile) {
            try ProvisioningProfile(data: Data([0x30]) + other)
        }
    }

    @Test func noProfileInATestBundle() {
        #expect(ProvisioningProfile.embedded(in: Bundle(for: BundleMarker.self)) == nil)
    }
}

private final class BundleMarker {}

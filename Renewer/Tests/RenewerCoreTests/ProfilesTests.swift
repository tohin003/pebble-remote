import Foundation
import Testing
@testable import RenewerCore

struct ProfilesTests {
    /// A stand-in for a .mobileprovision: the property list between signed-envelope bytes.
    func profile(bundle: String, created: String, expires: String) throws -> Data {
        let list: [String: Any] = [
            "AppIDName": "Pebble Remote",
            "CreationDate": Fixture.date(created),
            "ExpirationDate": Fixture.date(expires),
            "Entitlements": ["application-identifier": "AB12CD34EF.\(bundle)", "get-task-allow": true],
            "TeamName": "Jane Doe",
        ]
        let text = try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x2F, 0x1A, 0x06, 0x09]) + text + Data([0xA0, 0x82, 0x0D, 0x3E, 0x30, 0x82])
    }

    @Test func readsTheDatesAndTheBundleIdOnly() throws {
        let data = try profile(bundle: Fixture.bundleId, created: "2026-10-29T20:37:30Z", expires: "2026-11-05T20:37:30Z")
        let summary = try #require(ProvisioningProfiles.summary(of: data))
        #expect(summary.bundleId == Fixture.bundleId)
        #expect(summary.created == Fixture.date("2026-10-29T20:37:30Z"))
        #expect(summary.expires == Fixture.expires)
    }

    @Test func ignoresWhatIsNotAProfile() {
        #expect(ProvisioningProfiles.summary(of: Data("hello".utf8)) == nil)
        let empty = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict></dict></plist>"#
        #expect(ProvisioningProfiles.summary(of: Data(empty.utf8)) == nil)
    }

    @Test func newestForThisBundleIdOnly() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "renewer-profiles-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        try profile(bundle: Fixture.bundleId, created: "2026-10-22T20:00:00Z", expires: "2026-10-29T20:00:00Z")
            .write(to: folder.appending(path: "old.mobileprovision"))
        try profile(bundle: Fixture.bundleId, created: "2026-10-29T20:37:30Z", expires: "2026-11-05T20:37:30Z")
            .write(to: folder.appending(path: "current.mobileprovision"))
        // Newer, but the UI audit's runner, not the app.
        try profile(
            bundle: "io.github.tohin003.PebbleRemoteUIAudit.xctrunner", created: "2026-10-30T10:58:27Z",
            expires: "2026-11-06T10:58:27Z"
        ).write(to: folder.appending(path: "runner.mobileprovision"))
        try Data("not a profile".utf8).write(to: folder.appending(path: "broken.mobileprovision"))
        try profile(bundle: Fixture.bundleId, created: "2026-10-31T00:00:00Z", expires: "2026-11-07T00:00:00Z")
            .write(to: folder.appending(path: "notes.txt"))

        let newest = ProvisioningProfiles.newest(for: Fixture.bundleId, in: [folder.appending(path: "missing"), folder])
        #expect(newest?.expires == Fixture.expires)
        #expect(ProvisioningProfiles.newest(for: "io.github.someone.Else", in: [folder]) == nil)
    }
}

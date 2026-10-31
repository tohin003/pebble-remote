import Foundation
import Testing
@testable import RenewerCore

struct DevicesTests {
    /// The long-standing layout (Xcode 15 to 27): an iPhone on the cable, a watch, an iPad.
    static let legacy = #"""
    {
      "info": { "commandType": "devicectl.list.devices", "jsonVersion": 2, "outcome": "success" },
      "result": {
        "devices": [
          {
            "capabilities": [],
            "connectionProperties": {
              "authenticationType": "manualPairing", "pairingState": "paired", "transportType": "wired",
              "tunnelState": "connected", "tunnelTransportProtocol": "tcp"
            },
            "deviceProperties": { "developerModeStatus": "enabled", "name": "iPhone", "osVersionNumber": "27.2" },
            "hardwareProperties": {
              "deviceType": "iPhone", "marketingName": "iPhone 17", "platform": "iOS", "reality": "physical",
              "udid": "00008150-0000000000000000"
            },
            "identifier": "1A2B3C4D-1111-2222-3333-444455556666",
            "visibilityClass": "default"
          },
          {
            "connectionProperties": { "pairingState": "paired", "tunnelState": "unavailable" },
            "deviceProperties": { "name": "Watch" },
            "hardwareProperties": { "deviceType": "appleWatch", "platform": "watchOS" },
            "identifier": "9F9F9F9F-AAAA-BBBB-CCCC-DDDDEEEEFFFF"
          },
          {
            "connectionProperties": { "pairingState": "paired", "transportType": "localNetwork", "tunnelState": "disconnected" },
            "hardwareProperties": { "deviceType": "iPad", "platform": "iOS" },
            "identifier": "7E7E7E7E-AAAA-BBBB-CCCC-DDDDEEEEFFFF"
          }
        ]
      }
    }
    """#

    /// The newer layout devicectl announces (`properties.<category>.<field>`), some fields wrapped as {"value": ...},
    /// after a line printed before the document.
    static let newer = #"""
    Note: the legacy fields are deprecated.
    {
      "result": {
        "devices": [
          {
            "identifier": "5C5C5C5C-1111-2222-3333-444455556666",
            "properties": {
              "connection": { "transportType": "localNetwork" },
              "hardware": { "deviceType": "iPhone", "platform": { "value": "iOS" }, "udid": "00008150-0000000000000001" },
              "pairing": { "state": "paired" },
              "tunnel": { "state": "disconnected" }
            }
          }
        ]
      }
    }
    """#

    @Test func readsTheLongStandingLayout() throws {
        let devices = try DeviceList.parse(Data(Self.legacy.utf8))
        #expect(devices.count == 3)
        #expect(devices[0].isIPhone)
        #expect(devices[0].link == .cable)
        #expect(devices[0].udid == "00008150-0000000000000000")
        #expect(!devices[1].isIPhone)
        #expect(!devices[2].isIPhone, "an iPad is not the iPhone")
        let found = DeviceList.reachability(of: devices, preferring: nil)
        #expect(found == .reachable(devices[0], .cable))
    }

    @Test func readsTheNewerLayout() throws {
        let devices = try DeviceList.parse(Data(Self.newer.utf8))
        #expect(devices.count == 1)
        #expect(devices[0].isIPhone)
        #expect(devices[0].isPaired)
        #expect(devices[0].link == .network)
    }

    @Test func outOfReachUnpairedAndUnreadable() throws {
        #expect(Fixture.iPhone(tunnel: "unavailable", transport: nil).link == nil)
        #expect(Fixture.iPhone(tunnel: "disconnected", transport: "localNetwork").link == .network)
        #expect(Fixture.iPhone(tunnel: "connected", transport: nil).link == .other)
        var unpaired = Fixture.iPhone()
        unpaired.pairingState = "unpaired"
        #expect(unpaired.link == nil)

        #expect(DeviceList.reachability(of: [Fixture.iPhone(tunnel: "unavailable", transport: nil)], preferring: nil)
            == .unreachable(knownPhone: true))
        #expect(DeviceList.reachability(of: [unpaired], preferring: nil) == .unreachable(knownPhone: false))
        #expect(DeviceList.reachability(of: [], preferring: nil) == .unreachable(knownPhone: false))

        #expect(throws: DeviceListError.self) { try DeviceList.parse(Data("no devices here".utf8)) }
        #expect(throws: DeviceListError.self) { try DeviceList.parse(Data(#"{"result": {}}"#.utf8)) }
    }

    @Test func theRecordedIPhoneComesFirst() {
        let first = Fixture.iPhone("1A2B3C4D-1111-2222-3333-444455556666", udid: "00008150-0000000000000000")
        let second = Fixture.iPhone("2B2B2B2B-1111-2222-3333-444455556666", udid: "00008150-0000000000000002")
        #expect(DeviceList.reachability(of: [first, second], preferring: nil) == .several([first, second]))
        #expect(DeviceList.reachability(of: [first, second], preferring: "00008150-0000000000000002")
            == .reachable(second, .cable))
        #expect(DeviceList.reachability(of: [first, second], preferring: "1a2b3c4d-1111-2222-3333-444455556666")
            == .reachable(first, .cable))

        // The recorded iPhone out of reach is never swapped for another one.
        let away = Fixture.iPhone("1A2B3C4D-1111-2222-3333-444455556666", tunnel: "unavailable", transport: nil)
        #expect(DeviceList.reachability(of: [away, second], preferring: away.identifier)
            == .unreachable(knownPhone: true))
        // A recorded device that isn't paired any more (a new iPhone): the one reachable iPhone.
        #expect(DeviceList.reachability(of: [second], preferring: "FFFFFFFF-0000-0000-0000-000000000000")
            == .reachable(second, .cable))
    }

    @Test func onlyPlainIdentifiersAreKept() throws {
        let odd = #"{"result": {"devices": [{"identifier": "x; rm -rf ~", "hardwareProperties": {"platform": "iOS"}}]}}"#
        #expect(try DeviceList.parse(Data(odd.utf8)).isEmpty)
        #expect(DeviceList.isPlainIdentifier("00008150-0000000000000000"))
        #expect(!DeviceList.isPlainIdentifier("--force"))
        #expect(!DeviceList.isPlainIdentifier(""))
    }
}

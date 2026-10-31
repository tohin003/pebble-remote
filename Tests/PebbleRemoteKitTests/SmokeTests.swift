import Foundation
import Testing
@testable import PebbleRemoteKit

@Test func moduleLoads() {
    #expect(Bool(true))
}

@Test func pairingLinkParses() throws {
    let link = try #require(PairingLink(string: "pebble-remote://pair?v=1&bid=b1&name=Studio%20Mac&pin=AbC_d-1&code=xyz&ep=192.168.1.20:47800&ep=%5Bfe80::1%5D:47800&ep=mac.tail1.ts.net:47800"))
    #expect(link.macName == "Studio Mac")
    #expect(link.endpoints.map(\.routeKind) == [.lan, .lan, .tailscale])
    #expect(link.endpoints[1].host == "fe80::1")
    #expect(PairingLink(string: "pebble-remote://pair?v=2&bid=b&pin=p&code=c&ep=h:1") == nil)
}

@Test func pairingLinkToleratesRawBracketsAndOpenedURLs() throws {
    let raw = try #require(PairingLink(string: "  pebble-remote://pair?v=1&bid=b1&name=Studio%20Mac&pin=p&code=c&ep=[fe80::1]:47800\n"))
    #expect(raw.macName == "Studio Mac")
    #expect(raw.endpoints.first?.host == "fe80::1")
    let opened = try #require(URL(string: "pebble-remote://pair?v=1&bid=b1&name=Studio%20Mac&pin=p&code=c&ep=%5Bfe80::1%5D:47800"))
    #expect(PairingLink(url: opened)?.macName == "Studio Mac")
    #expect(PairingLink(string: "https://example.com/pair?v=1") == nil)
}

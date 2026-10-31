import Foundation
import Network
import Testing

@testable import PebbleRemoteKit

// Lane B: finding the Mac again by Bonjour after DHCP moved it (contract 3.1).
@Suite("Lane B: Bonjour rediscovery")
struct BonjourDiscoveryTests {
    @Test func matchesTheBridgeByItsTXTRecord() {
        #expect(BonjourBridgeDiscovery.matches(txt: ["v": "1", "bid": "bridge-1"], serviceName: "x", bridgeID: "bridge-1"))
        #expect(BonjourBridgeDiscovery.matches(txt: ["bid": "bridge-1"], serviceName: "x", bridgeID: "bridge-1"))
        #expect(!BonjourBridgeDiscovery.matches(txt: ["v": "1", "bid": "other"], serviceName: "bridge-1", bridgeID: "bridge-1"))
        #expect(!BonjourBridgeDiscovery.matches(txt: ["v": "2", "bid": "bridge-1"], serviceName: "x", bridgeID: "bridge-1"))
        // No TXT: an instance named by the bridge id (C6).
        #expect(BonjourBridgeDiscovery.matches(txt: [:], serviceName: "bridge-1", bridgeID: "bridge-1"))
        #expect(!BonjourBridgeDiscovery.matches(txt: [:], serviceName: "Studio Mac", bridgeID: "bridge-1"))
    }

    @Test func resolvedAddressesBecomeRaceEndpoints() throws {
        let v4 = BonjourBridgeDiscovery.endpoint(
            from: .hostPort(host: .ipv4(try #require(IPv4Address("192.168.1.31"))), port: 47800))
        #expect(v4 == Endpoint(host: "192.168.1.31", port: 47800) && v4?.routeKind == .lan)
        let v6 = BonjourBridgeDiscovery.endpoint(
            from: .hostPort(host: .ipv6(try #require(IPv6Address("fe80::1"))), port: 47800))
        #expect(v6?.host.hasPrefix("fe80::1") == true && v6?.port == 47800)
        #expect(BonjourBridgeDiscovery.endpoint(from: .service(name: "b", type: "_x._tcp", domain: "local", interface: nil)) == nil)
    }

    @Test func aNewAddressIsRacedAtOnceWhileWaitingToRetry() async throws {
        var configuration = LiveHarness.fast
        configuration.backoff = Backoff(initial: .seconds(20), maximum: .seconds(30))
        let h = try await LiveHarness.make(configuration: configuration)
        let moved = Endpoint(host: "192.168.1.31", port: 47800)
        h.bridge.set(.unreachable(after: .zero), for: LiveHarness.lan)  // DHCP gave the Mac another address
        await h.client.connect(to: h.mac)
        #expect(h.discovery.watchedBridge == h.bridge.bridgeID)
        try await eventually("waiting to retry") {
            if case .reconnecting(_, let next?) = await h.phase() { return next > Date() } else { return false }
        }
        h.discovery.find([moved])
        try await h.connected()
        #expect(await h.client.connectionStatus.endpoint == moved)
        // Found again with nothing new: no extra race.
        let opens = h.bridge.opens.count
        h.discovery.find([moved])
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.bridge.opens.count == opens)
        await h.client.disconnect()
        #expect(h.discovery.watchedBridge == nil)
    }
}

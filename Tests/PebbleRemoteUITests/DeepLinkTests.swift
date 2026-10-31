import Foundation
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// pebble-remote:// links the system hands the app.
struct DeepLinkTests {
    private func link(_ text: String) throws -> DeepLink? {
        DeepLink(url: try #require(URL(string: text)))
    }

    @Test func chatLinkOpensThatChat() throws {
        #expect(try link("pebble-remote://chat/abc-123") == .chat("abc-123"))
    }

    @Test func chatIDIsDecodedOnce() throws {
        #expect(try link("pebble-remote://chat/a%20b%2525") == .chat("a b%25"))
    }

    @Test func reviewsLink() throws {
        #expect(try link("pebble-remote://reviews") == .reviews)
        #expect(try link("PEBBLE-REMOTE://Reviews") == .reviews)
    }

    @Test func pairingLinkCarriesTheLink() throws {
        let opened = try link("pebble-remote://pair?v=1&bid=b1&name=Studio&pin=p1&code=c1&ep=10.0.0.2:7443")
        guard case .pair(let pairing) = opened else {
            Issue.record("expected a pairing link, got \(String(describing: opened))")
            return
        }
        #expect(pairing.bridgeID == "b1")
        #expect(pairing.macName == "Studio")
        #expect(pairing.endpoints == [Endpoint(host: "10.0.0.2", port: 7443)])
    }

    @Test(arguments: [
        "https://chat/abc",  // another scheme
        "pebble-remote://chat/",  // no id
        "pebble-remote://chat/a/b",  // more than one segment
        "pebble-remote://settings",  // not a route the app has
        "pebble-remote://pair?v=2&bid=b1&pin=p&code=c&ep=10.0.0.2:7443",  // a version this app doesn't speak
    ])
    func rejected(_ text: String) throws {
        #expect(try link(text) == nil)
    }
}

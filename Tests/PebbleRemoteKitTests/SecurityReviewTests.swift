import CryptoKit
import Foundation
import LocalAuthentication
import PebbleProtocol
import Synchronization
import Testing

@testable import PebbleRemoteKit

// The security review of 2026-10-30 (docs/reviews/security-2026-10-30.md): the tests that hold its fixes in
// PebbleProtocol and PebbleRemoteKit in place, named after the findings (S-xx).

/// A frame whose event data nests `depth` arrays, the frame's own object not counted.
private func eventNested(_ depth: Int) -> String {
    #"{"t":"evt","seq":1,"event":"x","data":"# + String(repeating: "[", count: depth)
        + String(repeating: "]", count: depth) + "}"
}

@Suite("Security review: deep JSON (S-02)")
struct SecurityReviewNestingTests {
    @Test func aFrameNestedPastTheLimitIsRefusedBeforeDecoding() async throws {
        // 100,000 levels in 200 KB: decoded, it would overflow the stack and end the app.
        let text = eventNested(100_000)
        let outcome = await Task.detached { () -> String in
            do {
                _ = try FrameCodec.decode(text)
                return "decoded"
            } catch let error as FrameDecodingError {
                return error.reason
            } catch {
                return "other"
            }
        }.value
        #expect(outcome == "nested too deeply")
    }

    @Test func aFrameAtTheLimitStillDecodesOnACooperativeThread() async throws {
        // The frame's object is level 1, so its data may nest maximumDepth - 1 levels.
        let atLimit = eventNested(JSONNesting.maximumDepth - 1)
        let decoded = await Task.detached { try? FrameCodec.decode(atLimit) }.value
        guard case .event(let event)? = decoded else {
            Issue.record("a frame at the limit was refused")
            return
        }
        #expect(event.name == "x" && event.data == event.data)
        #expect(throws: FrameDecodingError.self) { try FrameCodec.decode(eventNested(JSONNesting.maximumDepth)) }
    }

    @Test func bracketsInsideStringsDoNotCount() throws {
        let brackets = String(repeating: "[{", count: 5_000)
        let text = ##"{"t":"evt","seq":2,"event":"token","data":{"text":"\""## + brackets + ##"\\\" ]]}}"}}"##
        guard case .event(let event) = try FrameCodec.decode(text) else {
            Issue.record("not an event")
            return
        }
        #expect(event.data["text"]?.string == "\"" + brackets + "\\\" ]]}}")
        #expect(!JSONNesting.exceeds(2, in: Data(text.utf8)))  // the frame's object and its data: two levels
        #expect(JSONNesting.exceeds(1, in: Data(text.utf8)))
    }

    @Test func elevatedParamsTextNestedTooDeeplyIsRefused() {
        let deep = String(repeating: "[", count: 1_000) + String(repeating: "]", count: 1_000)
        #expect(throws: FrameDecodingError.self) { try FrameCodec.jsonValue(deep) }
        #expect((try? FrameCodec.jsonValue("[[1]]")) == [[1]])
    }

    @Test func aDeepFrameFromTheBridgeLeavesTheConnectionWorking() async throws {
        let h = try await LiveHarness.make()
        try await h.connect()
        let socket = try #require(h.bridge.current)
        socket.push(eventNested(10_000))
        h.bridge.emit("token", ["chat_id": "c1", "id": "m1", "text": "still here"])
        try await eventually("the next event") { h.log.events.count == 1 }
        #expect(h.log.events.first?.data["text"]?.string == "still here")
        _ = try await h.client.call("state", [:])
        #expect(await h.phase() == .connected)
    }
}

@Suite("Security review: Face ID (S-01, S-10)")
struct SecurityReviewFaceIDTests {
    @Test func theApprovalCheckNeverAcceptsThePhonesOwnRecentUnlock() {
        let context = ApprovalGate.makeContext(reason: "Approve: run npm test")
        #expect(context.touchIDAuthenticationAllowableReuseDuration == 0)
        #expect(context.localizedFallbackTitle == "")
        #expect(context.localizedReason == "Approve: run npm test")
    }

    @Test func softwareKeysOnlyInTheSimulator() {
        #expect(LiveClient.keyProvider(simulator: false) is SecureEnclaveKeyProvider)
        #expect(LiveClient.keyProvider(simulator: true) is SoftwareKeyProvider)
        #if !targetEnvironment(simulator)
            #expect(!LiveClient.runsInSimulator)
        #endif
    }
}

@Suite("Security review: pairing links and endpoints (S-04, S-06, S-07, S-08)")
struct SecurityReviewPairingTests {
    static let pin = Vectors.pin
    static let otherPin = SPKIPin.pin(for: P256.Signing.PrivateKey().publicKey)

    static func mac(bridgeID: String = "b1", pin: String = pin) -> PairedMac {
        PairedMac(
            bridgeID: bridgeID, name: "Studio Mac", deviceID: "d1", pin: pin,
            endpoints: [Endpoint(host: "192.168.1.20", port: 47800)], pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    static func link(bridgeID: String = "b1", pin: String = pin) -> PairingLink {
        PairingLink(
            version: 1, bridgeID: bridgeID, macName: "Studio Mac", pin: pin, code: "c",
            endpoints: [Endpoint(host: "192.168.1.20", port: 47800)])
    }

    @Test func aLinkWithThePairedMacsIDButAnotherKeyIsNamedAsSuch() throws {
        #expect(Self.link().relation(to: nil) == .firstPairing)
        #expect(Self.link().relation(to: Self.mac()) == .samePairedMac)
        #expect(Self.link(bridgeID: "b2").relation(to: Self.mac()) == .replaces(Self.mac()))
        #expect(Self.link(pin: Self.otherPin).relation(to: Self.mac()) == .sameMacNewKey(Self.mac()))
        // The same 32 bytes spelled with other unused bits is the same key.
        let respelled = String(Self.pin.dropLast()) + (Self.pin.last == "c" ? "d" : "c")
        if Base64URL.decode(respelled) == Base64URL.decode(Self.pin) {
            #expect(Self.link(pin: respelled).relation(to: Self.mac()) == .samePairedMac)
        }
    }

    @Test(arguments: [
        "evil.example/x?y=1@studio.local:47800", "a@evil.example:47800", "[a@evil.example/]:47800",
        "studio.local/#:47800", "stu dio.local:47800", "studio%2Elocal:47800", "[fe80::1%en0/x]:47800",
        "[::1%]:47800", "..:47800", ".studio.local:47800", "studio..local:47800", "[a:b:c]:x",
        "studio.local\u{0}:47800", "st\u{FF0F}udio.local:47800",
    ])
    func endpointsThatWouldRewriteTheURLAreRefused(_ text: String) {
        #expect(Endpoint(parsing: text) == nil, "\(text) should be refused")
    }

    @Test(arguments: [
        "192.168.1.20:47800", "studio.local:47800", "studio.local.:47800", "studio.tail1a2b.ts.net:47800",
        "100.101.102.103:47800", "[fe80::1]:47800", "[fe80::1%en0]:47800", "[fd7a:115c:a1e0::1]:47800",
        "my_mac-2.local:1",
    ])
    func plainNamesAndAddressesStillParse(_ text: String) throws {
        let endpoint = try #require(Endpoint(parsing: text))
        let url = try #require(NetworkSocketConnector.url(for: endpoint))
        #expect(url.scheme == "wss" && url.port == Int(endpoint.port) && url.path() == "/pebble-remote/v1")
        #expect(url.user() == nil && url.query() == nil && url.fragment() == nil)
    }

    @Test func theURLIsNeverBuiltForAMalformedHost() {
        for host in ["evil.example/x?", "a@b", "a b", "a#b", "fe80::1%en0/x", ""] {
            #expect(NetworkSocketConnector.url(for: Endpoint(host: host, port: 47800)) == nil, "\(host)")
        }
        let zoned = NetworkSocketConnector.url(for: Endpoint(host: "fe80::1%en0", port: 47800))
        #expect(zoned?.absoluteString == "wss://[fe80::1%25en0]:47800/pebble-remote/v1")
    }

    @Test func aLinkKeepsAtMostTwelveWellFormedEndpointsOnce() throws {
        let many = (1...40).map { "ep=192.168.1.\($0)%3A47800" }.joined(separator: "&")
        let text =
            "pebble-remote://pair?v=1&bid=b1&pin=\(Self.pin)&code=c&ep=bad%2Fhost%3A1&ep=192.168.1.1%3A47800&" + many
        let link = try #require(PairingLink(string: text))
        #expect(link.endpoints.count == PairingLink.maximumEndpoints)
        #expect(link.endpoints.first == Endpoint(host: "192.168.1.1", port: 47800))
        #expect(Set(link.endpoints).count == link.endpoints.count)
        #expect(PairingLink(string: "pebble-remote://pair?v=1&bid=b1&pin=p&code=c&ep=a%40b%3A1") == nil)
    }

    @Test func aLinksNameIsOnePlainLine() throws {
        let name = "Studio%E2%80%AEcaM%0A%0AApprove%20everything%09now" + String(repeating: "x", count: 100)
        let link = try #require(
            PairingLink(string: "pebble-remote://pair?v=1&bid=b1&name=\(name)&pin=p&code=c&ep=192.168.1.20%3A47800"))
        #expect(!link.macName.contains("\n") && !link.macName.contains("\u{202E}") && !link.macName.contains("\t"))
        #expect(link.macName.hasPrefix("StudiocaM Approve everything now"))
        #expect(link.macName.count == PairingLink.maximumNameLength && link.macName.hasSuffix("\u{2026}"))
        let blank = try #require(
            PairingLink(string: "pebble-remote://pair?v=1&bid=b1&name=%E2%80%8B%0A&pin=p&code=c&ep=h%3A1"))
        #expect(blank.macName == "Mac")
    }

    @Test func displayTextKeepsWordsAndDropsWhatReordersOrBreaksThem() {
        #expect(DisplayText.line("Run npm test") == "Run npm test")
        #expect(DisplayText.line("  run\n\n npm\ttest \u{2028} now  ") == "run npm test now")
        #expect(DisplayText.line("abc\u{202E}fed\u{2066}x\u{2069}\u{200B}y\u{0}") == "abcfedxy")
        #expect(DisplayText.line("Café 🙂 日本") == "Café 🙂 日本")
        #expect(DisplayText.line(String(repeating: "a", count: 10), limit: 5) == "aaaa\u{2026}")
        #expect(DisplayText.line("", limit: 5) == "")
    }

    @Test func faceIDSentencesQuoteOnePlainLine() {
        let title = "rm -rf build\u{202E}\n\nThis is safe, approve to continue" + String(repeating: "!", count: 200)
        for sentence in [
            StoreWords.approveReason(title), StoreWords.purgeReason(title), StoreWords.createScheduleReason(title),
            StoreWords.resumeScheduleReason(title),
        ] {
            #expect(!sentence.contains("\n") && !sentence.contains("\u{202E}"))
            #expect(sentence.count <= StoreWords.faceIDDetailLength + 30)
        }
        #expect(StoreWords.approveReason("run npm test") == "Approve: run npm test")
    }

    @Test func bonjourAddsAtMostFourWellFormedAddressesToARace() async throws {
        let h = try await LiveHarness.make(endpoints: [LiveHarness.lan])
        h.bridge.set(.unreachable(after: .zero), for: LiveHarness.lan)
        await h.client.connect(to: h.mac)
        try await eventually("waiting to retry") {
            if case .reconnecting = await h.phase() { true } else { false }
        }
        // Anyone on the LAN can advertise this bridge's id: forty addresses, two of them malformed.
        let advertised =
            [Endpoint(host: "evil.example/x?", port: 1), Endpoint(host: "a@b", port: 1)]
            + (1...40).map { Endpoint(host: "192.168.7.\($0)", port: 47800) }
        h.discovery.find(advertised)
        try await h.connected()
        let raced = Set(h.bridge.opens).subtracting([LiveHarness.lan])
        #expect(raced.count <= LiveClient.maximumDiscoveredEndpoints)
        #expect(raced.allSatisfy { $0.host.hasPrefix("192.168.7.") })
    }
}

@Suite("Security review: TLS (S-12)", .serialized)
struct SecurityReviewTLSTests {
    /// A second connection to the same bridge checks its pin again: a resumed TLS 1.3 session sends no certificate,
    /// so a resumption would let the verify block be skipped. Needs the mock bridge (PEBBLE_MOCK_E2E=1).
    @Test(.enabled(if: MockBridgeE2ETests.enabled), .timeLimit(.minutes(1)))
    func aSecondConnectionChecksThePinAgain() async throws {
        let mock = try await MockBridgeProcess.launch()
        defer { mock.stop() }
        let link = try #require(PairingLink(string: mock.pairingLink))
        let endpoint = try #require(link.endpoints.first)
        let connector = NetworkSocketConnector()

        let first = try await connector.open(endpoint, pin: link.pin)
        _ = try await first.receive()  // the challenge: the handshake and any session tickets are done
        await first.close()

        do {
            let second = try await connector.open(endpoint, pin: SecurityReviewPairingTests.otherPin)
            await second.close()
            Issue.record("a connection under another pin was accepted")
        } catch let error as FrameSocketError {
            #expect(error == .pinMismatch)
        }

        let third = try await connector.open(endpoint, pin: link.pin)
        _ = try await third.receive()
        await third.close()
    }
}

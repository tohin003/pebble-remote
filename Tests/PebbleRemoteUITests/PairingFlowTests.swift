import Foundation
import PebbleDesign
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Waits (briefly) until the condition holds.
@MainActor
func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Lane X, contract X-1 on the pairing screens: once the phone has sent its pairing, the flow holds the six digits to
/// compare with the Mac's while the person confirms there; a pairing the Mac does not confirm ends in words that say
/// what to do; the person can leave the wait.
@MainActor
struct PairingFlowTests {
    private static let link = PairingLink(
        version: 1, bridgeID: "b1", macName: "Studio Mac", pin: "p1", code: "c1",
        endpoints: [Endpoint(host: "192.168.1.20", port: 47800)])
    private static let mac = PairedMac(
        bridgeID: "b1", name: "Studio Mac", deviceID: "d1", pin: "p1", endpoints: link.endpoints,
        pairedAt: Date(timeIntervalSince1970: 1_800_000_000))

    private static func make(code: String = "035072") -> (ShellProbeClient, PebbleRemoteModel, PairingFlow) {
        let probe = ShellProbeClient(code: code)
        return (probe, PebbleRemoteModel(store: RemoteStore(client: probe)), PairingFlow())
    }

    @Test func theCodeShowsWhileTheMacWaitsAndGoesWhenPairingEnds() async {
        let (probe, model, flow) = Self.make()
        let pairing = Task { await flow.pair(Self.link, model: model) }
        #expect(await waitUntil { flow.code?.digits == "035072" })
        #expect(flow.code?.grouped == "035 072")
        #expect(flow.isPairing && flow.problem == nil)
        #expect(model.store.pairedMac == nil)  // nothing is paired until the Mac confirms
        probe.macConfirms(Self.mac)
        await pairing.value
        #expect(flow.code == nil && !flow.isPairing && flow.problem == nil)
        #expect(model.store.pairedMac == Self.mac)
    }

    @Test func aPairingTheMacDidNotConfirmSaysWhatToDo() async {
        let (probe, model, flow) = Self.make()
        let pairing = Task { await flow.pair(Self.link, model: model) }
        #expect(await waitUntil { flow.code != nil })
        probe.macCancels()  // the Mac's `bye` `bad_code`: cancelled there, or its two minutes ran out
        await pairing.value
        #expect(flow.problem == AppCopy.Pairing.notConfirmed)
        #expect(flow.code == nil && !flow.isPairing)
        #expect(model.store.pairedMac == nil && model.store.notice == nil)
    }

    @Test func thePersonLeavingTheWaitSaysNothingAndKeepsNothing() async {
        let (probe, model, flow) = Self.make()
        let pairing = Task { await flow.pair(Self.link, model: model) }
        #expect(await waitUntil { flow.code != nil })
        flow.cancel()
        await pairing.value
        #expect(flow.problem == nil && flow.code == nil && !flow.isPairing)
        #expect(probe.events.contains("pairing cancelled"))
        #expect(model.store.pairedMac == nil && model.store.notice == nil)
    }

    @Test func theNextAttemptStartsClean() async {
        let (probe, model, flow) = Self.make()
        let first = Task { await flow.pair(Self.link, model: model) }
        #expect(await waitUntil { flow.code != nil })
        probe.macCancels()
        await first.value
        #expect(flow.problem != nil)
        // A new link, a new attempt: the old problem goes, and the code of this attempt shows.
        let (again, model2, _) = Self.make(code: "994460")
        let second = Task { await flow.pair(Self.link, model: model2) }
        #expect(await waitUntil { flow.code?.digits == "994460" })
        #expect(flow.problem == nil)
        again.macConfirms(Self.mac)
        await second.value
        #expect(model2.store.pairedMac == Self.mac)
    }

    @Test func aSecondPairingWhileOneWaitsIsIgnored() async {
        let (probe, model, flow) = Self.make()
        let first = Task { await flow.pair(Self.link, model: model) }
        #expect(await waitUntil { flow.code != nil })
        await flow.pair(Self.link, model: model)  // returns at once
        #expect(probe.events.filter { $0 == "pair" }.count == 1)
        probe.macConfirms(Self.mac)
        await first.value
    }

    @Test func theWordsForAPairingThatWasNotConfirmed() {
        for code in ["bad_code", "not_confirmed"] {
            #expect(PairingWords.message(for: RemoteCallError.transport(code)) == AppCopy.Pairing.notConfirmed)
        }
        #expect(PairingWords.message(for: RemoteCallError.cancelledByPerson) == nil)
    }
}

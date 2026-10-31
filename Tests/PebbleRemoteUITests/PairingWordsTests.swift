import PebbleDesign
import PebbleRemoteKit
import Testing

@testable import PebbleRemoteUI

/// Pairing failures the client reports as content-free codes get PebbleDesign's words; everything else keeps the
/// store's own notice (Pebble's or the bridge's words).
struct PairingWordsTests {
    @Test func unreachableMacSaysHowToReachIt() {
        #expect(PairingWords.message(for: RemoteCallError.transport("unreachable")) == AppCopy.Connection.unreachable)
    }

    @Test func aMacThatCantProveItselfIsNamedAsSuch() {
        #expect(PairingWords.message(for: RemoteCallError.transport("pin_mismatch")) == AppCopy.Connection.identityChanged)
        #expect(PairingWords.message(for: RemoteCallError.transport("wrong_bridge")) == AppCopy.Errors.wrongMac)
    }

    @Test func refusalsKeepTheBridgesWords() {
        let refusal = PersonFacingError(message: "This pairing link has expired or was already used.", code: "bad_code")
        #expect(PairingWords.message(for: RemoteCallError.refused(refusal)) == nil)
    }

    @Test func unknownCodesAndCancelsKeepTheStoresNotice() {
        #expect(PairingWords.message(for: RemoteCallError.transport("a_code_from_a_newer_client")) == nil)
        #expect(PairingWords.message(for: RemoteCallError.cancelledByPerson) == nil)
    }
}

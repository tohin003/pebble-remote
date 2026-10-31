import PebbleDesign
import PebbleRemoteKit
import SwiftUI

/// A connection problem that needs the person, with the one thing that fixes it when there is one (pair again).
struct ConnectionProblemRow: View {
    let problem: ConnectionProblem
    @Environment(PebbleRemoteModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: PebbleSpace.s2) {
            // Pebble's danger colour, not system orange: orange text on a white row is 2.2:1, under the 4.5:1 floor.
            Label(ConnectionWords.problemMessage(problem), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(PebbleColor.danger)
            if ConnectionWords.needsPairing(problem) {
                Button(AppCopy.Connection.pairAgain, systemImage: "qrcode", action: pairAgain)
                    .buttonStyle(.pebblePrimary)
            }
        }
    }

    /// Pairing again starts from the pairing screen: forget the old pairing, which no longer works.
    private func pairAgain() {
        Task { await model.forgetMac() }
    }
}

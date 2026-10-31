import Foundation
import PebbleRemoteKit

/// A pairing link waiting for the person's confirmation, identified for `sheet(item:)`.
struct PendingPairing: Identifiable, Equatable {
    let id = UUID()
    let link: PairingLink
}

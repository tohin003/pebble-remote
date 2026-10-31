import Foundation
import PebbleProtocol

// Lane Z, item 3: the composer's "/" commands. Pebble's catalogue is read when the person types "/"; a command goes to
// Pebble as an ordinary message (`send`), which answers it at once. The list never offers the words that settle a goal
// (the lead, 02:55): on the phone, goals are settled in the conversation's Details › Task, with Face ID.

extension RemoteStore {
    /// Pebble's typed commands (`command_catalogue`), checked as Pebble's window checks them. Quiet: a failure is not
    /// shown, since the composer only lists what it could read (the person can still type a command).
    public func commandCatalogue() async throws -> [PebbleCommand] {
        guard offers("command_catalogue") else { throw RemoteCallError.notImplemented("command_catalogue") }
        return PebbleCommand.catalogue(try await client.call("command_catalogue", [:]))
    }
}

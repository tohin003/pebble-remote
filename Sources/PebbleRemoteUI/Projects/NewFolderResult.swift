import PebbleDesign
import PebbleRemoteKit

/// How making a folder on the Mac came out, for the screen (proposal v0.6).
enum NewFolderResult: Equatable {
    /// The folder exists on the Mac, empty.
    case made(FolderEntry)
    /// The phone or the Mac refused, in words for the person: a name already there, a parent Pebble Remote may not use,
    /// a connection that dropped.
    case refused(String)
    /// The person cancelled Face ID: there is nothing to say.
    case cancelled
}

extension RemoteStore {
    /// "New Folder": makes the folder named `name` inside `parent` (the store asks for Face ID) and says how it went. The
    /// failure the store leaves in `notice` is taken here, to show where the person is, inside the sheet.
    func makeFolder(named name: String, in parent: String) async -> NewFolderResult {
        do {
            return .made(try await createFolder(named: name, in: parent))
        } catch RemoteCallError.cancelledByPerson {
            return .cancelled
        } catch {
            return .refused(takeNotice() ?? AppCopy.Errors.generic)
        }
    }
}

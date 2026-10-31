import AppKit
import Foundation
import RenewerCore

/// `PebbleRemoteRenewer` starts the menu-bar item (the LaunchAgent runs it at login).
/// `PebbleRemoteRenewer --check` prints what it sees and would do, and exits.
/// `--repo PATH` names Pebble Remote's repository (otherwise the app's Info.plist does; install.sh writes it).
@main
@MainActor
enum Entry {
    static func main() {
        let arguments = CommandLine.arguments
        let configuration = AppConfiguration.resolve(
            arguments: arguments, environment: ProcessInfo.processInfo.environment, bundle: .main)
        if arguments.contains("--check") {
            Task {
                let status = await CheckCommand.run(configuration)
                exit(status)
            }
            dispatchMain()
        }
        guard InstanceLock.acquire(configuration.paths) else {
            FileLog(url: configuration.paths.logFile).writeNow("Another copy is already running, so this one quit.")
            exit(0)
        }
        RenewerApp.main()
    }
}

/// One item at a time: the first copy holds an exclusive lock on renewer.lock for its whole life (the system lets go
/// when the process ends, even after a crash), and a second copy finds it held and quits. Two copies would build in
/// the same worktree at once.
enum InstanceLock {
    static func acquire(_ paths: RenewerPaths) -> Bool {
        try? OwnerOnlyFile.makeFolder(paths.supportFolder)
        let descriptor = open(paths.lockFile.path(percentEncoded: false), O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return true }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }
        return true
    }
}

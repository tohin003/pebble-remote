import Foundation
import RenewerCore

/// One subprocess: hold-status.sh, devicectl or renew.sh.
struct RunRequest: Sendable {
    var executable: URL
    var arguments: [String]
    var environment: [String: String]
    var directory: URL?
    var timeout: TimeInterval
    /// renew.sh: standard error joins standard output, and the lines are kept as RenewOutput.
    var streamsLines = false
    /// Called with each "renew.sh: ..." line as it arrives (on a background queue).
    var onLine: (@Sendable (String) -> Void)? = nil
}

struct RunResult: Sendable {
    var status: Int32
    var timedOut = false
    var launchFailure: String?
    /// Standard output, when lines aren't streamed (devicectl's list).
    var output = Data()
    var lines = RenewOutput()
}

enum Runner {
    static let outputLimit = 8 << 20

    /// The environment for every subprocess: the system's own tools first (/usr/local/bin may hold broken Intel builds
    /// of git), and Xcode chosen for this process alone.
    static func environment(developerDir: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["DEVELOPER_DIR"] = developerDir
        return environment
    }

    /// Runs off the main thread; the menu stays live while a build goes on.
    static func run(_ request: RunRequest) async -> RunResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(request))
            }
        }
    }

    static func runBlocking(_ request: RunRequest) -> RunResult {
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        if let directory = request.directory { process.currentDirectoryURL = directory }
        let pipe = Pipe()
        process.standardOutput = pipe
        if request.streamsLines {
            process.standardError = pipe
        } else {
            process.standardError = FileHandle.nullDevice
        }
        process.standardInput = FileHandle.nullDevice
        let started = Date()
        do {
            try process.run()
        } catch {
            return RunResult(status: -1, launchFailure: error.localizedDescription)
        }
        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem { Runner.stop(pid) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + request.timeout, execute: watchdog)

        var result = RunResult(status: 0)
        var pending = Data()
        let reader = pipe.fileHandleForReading
        // Read until the pipe ends, or until the script has exited and the pipe has stayed quiet for 3 s: a child that
        // outlives it (Xcode's build service, say) can hold the pipe open, which left the menu on "Renewing…".
        let descriptor = reader.fileDescriptor
        var quietSince: Date?
        while true {
            var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 500) > 0 else {
                if process.isRunning { continue }
                if let since = quietSince {
                    if Date().timeIntervalSince(since) >= 3 { break }
                } else {
                    quietSince = Date()
                }
                continue
            }
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            quietSince = nil
            if request.streamsLines {
                pending.append(chunk)
                var start = pending.startIndex
                while let newline = pending[start...].firstIndex(of: 0x0A) {
                    take(String(decoding: pending[start..<newline], as: UTF8.self), into: &result.lines, request)
                    start = pending.index(after: newline)
                }
                pending = Data(pending[start...])
            } else if result.output.count < outputLimit {
                result.output.append(chunk)
            }
        }
        if !pending.isEmpty { take(String(decoding: pending, as: UTF8.self), into: &result.lines, request) }
        process.waitUntilExit()
        watchdog.cancel()
        result.status = process.terminationStatus
        result.timedOut = process.terminationReason == .uncaughtSignal
            && Date().timeIntervalSince(started) >= request.timeout
        return result
    }

    static func take(_ raw: String, into lines: inout RenewOutput, _ request: RunRequest) {
        let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        lines.add(line)
        if line.hasPrefix(RenewScript.prefix) { request.onLine?(line) }
    }

    /// After the timeout: the script's children first (xcodebuild, devicectl), then the script.
    static func stop(_ pid: Int32) {
        let pkill = Process()
        pkill.executableURL = URL(filePath: "/usr/bin/pkill")
        pkill.arguments = ["-TERM", "-P", String(pid)]
        do {
            try pkill.run()
            pkill.waitUntilExit()
        } catch {}
        _ = kill(pid, SIGTERM)
    }
}

/// The two checks before a renewal: Pebble's HOLD, and the iPhone.
struct Probes: Sendable {
    let configuration: AppConfiguration
    let log: FileLog?

    /// scripts/hold-status.sh: exit 0 no HOLD, 3 a HOLD. Never `--force` anything.
    func hold() async -> HoldState {
        let result = await Runner.run(RunRequest(
            executable: configuration.holdScript, arguments: [],
            environment: Runner.environment(developerDir: configuration.developerDir),
            directory: configuration.repository, timeout: configuration.probeTimeout))
        if let failure = result.launchFailure {
            log?.write("hold-status.sh couldn't start: \(failure)")
            return .unknown
        }
        return HoldState(exitStatus: result.status)
    }

    /// `xcrun devicectl list devices`: lists what the Mac knows; it never changes anything on the iPhone.
    func phone(preferring device: String?) async -> Reachability {
        let result = await Runner.run(RunRequest(
            executable: URL(filePath: "/usr/bin/xcrun"),
            arguments: ["devicectl", "list", "devices", "--quiet", "--timeout", "30", "--json-output", "-"],
            environment: Runner.environment(developerDir: configuration.developerDir),
            directory: nil, timeout: configuration.probeTimeout))
        guard result.launchFailure == nil, result.status == 0, let devices = try? DeviceList.parse(result.output) else {
            log?.write("devicectl's device list couldn't be read (exit \(result.status)).")
            return .unreadable
        }
        return DeviceList.reachability(of: devices, preferring: device)
    }
}

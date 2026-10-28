import AppKit
import Foundation

public enum QuitResult: Sendable {
    case notRunning, quit, stillRunning
}

public enum LaunchError: Error, Equatable {
    case claudeNotFound
}

public protocol ClaudeControlling: Sendable {
    /// nil = Claude not running; .some(nil) = running on its default data dir.
    func runningDataDir() async -> URL??
    func quit(timeout: TimeInterval) async -> QuitResult
    func forceQuit() async
    func launch(dataDir: URL?) async throws
}

public enum ProcessArgs {
    /// argv of another process via sysctl KERN_PROCARGS2.
    public static func arguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        // Layout: argc (Int32), exec path, NUL padding, then argc NUL-terminated strings.
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var i = MemoryLayout<Int32>.size
        while i < size && buffer[i] != 0 { i += 1 }  // exec path
        while i < size && buffer[i] == 0 { i += 1 }  // padding
        var args: [String] = []
        while args.count < Int(argc) && i < size {
            let start = i
            while i < size && buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    public static func userDataDir(from args: [String]) -> URL? {
        for (i, arg) in args.enumerated() {
            if arg.hasPrefix("--user-data-dir=") {
                return URL(fileURLWithPath: String(arg.dropFirst("--user-data-dir=".count)), isDirectory: true)
            }
            if arg == "--user-data-dir", i + 1 < args.count {
                return URL(fileURLWithPath: args[i + 1], isDirectory: true)
            }
        }
        return nil
    }
}

/// Which profile owns the running Claude's data dir. Paths are compared after standardizing.
public func matchProfile(_ running: URL??, in profiles: [Profile], defaultDir: URL) -> Profile? {
    guard let running else { return nil }
    let target = (running ?? defaultDir).standardizedFileURL.path
    return profiles.first { $0.resolvedDataDir(defaultDir: defaultDir).standardizedFileURL.path == target }
}

public final class ClaudeLauncher: ClaudeControlling {
    public static let bundleId = "com.anthropic.claudefordesktop"

    public init() {}

    static func launchArguments(dataDir: URL?) -> [String] {
        dataDir.map { ["--user-data-dir=\($0.path)"] } ?? []
    }

    var appURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleId) { return url }
        let fallback = URL(fileURLWithPath: "/Applications/Claude.app")
        return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
    }

    private func runningApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId).first { !$0.isTerminated }
    }

    public func runningDataDir() async -> URL?? {
        guard let app = runningApp() else { return nil }
        guard let args = ProcessArgs.arguments(pid: app.processIdentifier) else {
            Log.error("Could not read Claude's arguments (pid \(app.processIdentifier))")
            return .some(nil)
        }
        return .some(ProcessArgs.userDataDir(from: args))
    }

    public func quit(timeout: TimeInterval) async -> QuitResult {
        guard let app = runningApp() else { return .notRunning }
        app.terminate()
        return await waitForExit(app, timeout: timeout) ? .quit : .stillRunning
    }

    public func forceQuit() async {
        guard let app = runningApp() else { return }
        app.forceTerminate()
        _ = await waitForExit(app, timeout: 5)
    }

    public func launch(dataDir: URL?) async throws {
        guard let appURL else { throw LaunchError.claudeNotFound }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = Self.launchArguments(dataDir: dataDir)
        config.createsNewApplicationInstance = true
        config.activates = true
        Log.info("Launching Claude with \(config.arguments)")
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }

    private func waitForExit(_ app: NSRunningApplication, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !app.isTerminated && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return app.isTerminated
    }
}

import Foundation
import os

/// Appends to ~/Library/Logs/ClaudeSwitch.log and mirrors to os_log.
/// Never pass cookies, keys or tokens here.
public enum Log {
    private static let logger = Logger(subsystem: "com.luke.claudeswitch", category: "app")
    private static let lock = NSLock()

    public static func info(_ s: String) { write("INFO", s); logger.info("\(s, privacy: .public)") }
    public static func error(_ s: String) { write("ERROR", s); logger.error("\(s, privacy: .public)") }

    private static func write(_ level: String, _ s: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(s)\n"
        lock.lock(); defer { lock.unlock() }
        let url = Paths.logFile
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(line.utf8))
        } else {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(line.utf8).write(to: url)
        }
    }
}

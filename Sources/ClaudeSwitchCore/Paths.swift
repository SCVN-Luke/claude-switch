import Foundation

public enum Paths {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// ~/Library/Application Support/ClaudeSwitch
    public static var appSupport: URL {
        home.appendingPathComponent("Library/Application Support/ClaudeSwitch", isDirectory: true)
    }

    /// Claude Desktop's own data dir, used when a profile has no dataDir.
    public static var claudeDefaultDataDir: URL {
        home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    }

    public static var logFile: URL {
        home.appendingPathComponent("Library/Logs/ClaudeSwitch.log")
    }
}

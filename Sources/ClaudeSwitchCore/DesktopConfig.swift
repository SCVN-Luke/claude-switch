import Foundation

public struct MCPServerEntry: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    /// Executable name or URL host — never args or env, which may hold secrets.
    public var detail: String

    public init(name: String, detail: String) {
        self.name = name
        self.detail = detail
    }
}

public enum ConfigCopyOutcome: Equatable, Sendable {
    case copied, alreadyExists, notFound
}

public enum ConfigError: Error, Equatable, Sendable {
    case sourceUnreadable, targetUnreadable, targetNotSignedIn
}

/// Per-profile Claude Desktop settings that can be carried to another profile:
/// local MCP servers (`claude_desktop_config.json`) and disabled-tool lists
/// (`mcp-user-tool-toggles.json`). Values are copied verbatim and never logged.
public enum DesktopConfig {
    static let configFile = "claude_desktop_config.json"
    static let togglesFile = "mcp-user-tool-toggles.json"

    public static func mcpServers(in dataDir: URL) -> [MCPServerEntry] {
        guard let obj = try? readObject(dataDir.appendingPathComponent(configFile)),
              let servers = obj["mcpServers"] as? [String: Any] else { return [] }
        return servers.map { name, value in
            let entry = value as? [String: Any] ?? [:]
            var detail = ""
            if let command = entry["command"] as? String {
                detail = URL(fileURLWithPath: command).lastPathComponent
            } else if let url = (entry["url"] as? String).flatMap(URL.init(string:)) {
                detail = url.host ?? ""
            }
            return MCPServerEntry(name: name, detail: detail)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Adds the named servers to the target's config. Existing names are left alone;
    /// the target's other keys are kept and the previous file is saved as `.bak`.
    public static func copyMCPServers(_ names: [String], from source: URL, to target: URL) throws
        -> [String: ConfigCopyOutcome] {
        guard let src = try? readObject(source.appendingPathComponent(configFile)) else {
            throw ConfigError.sourceUnreadable
        }
        let srcServers = src["mcpServers"] as? [String: Any] ?? [:]
        let targetURL = target.appendingPathComponent(configFile)
        let original = try? Data(contentsOf: targetURL)
        var dst: [String: Any] = [:]
        if let original {
            guard let obj = (try? JSONSerialization.jsonObject(with: original)) as? [String: Any] else {
                throw ConfigError.targetUnreadable
            }
            dst = obj
        }
        var dstServers = dst["mcpServers"] as? [String: Any] ?? [:]

        var result: [String: ConfigCopyOutcome] = [:]
        for name in names {
            if dstServers[name] != nil {
                result[name] = .alreadyExists
            } else if let server = srcServers[name] {
                dstServers[name] = server
                result[name] = .copied
            } else {
                result[name] = .notFound
            }
        }
        guard result.values.contains(.copied) else { return result }

        dst["mcpServers"] = dstServers
        if let original { try original.write(to: target.appendingPathComponent(configFile + ".bak"), options: .atomic) }
        try write(dst, to: targetURL)
        return result
    }

    /// Unions the source account's disabled tools into the target account's list.
    /// Returns how many entries were added.
    @discardableResult
    public static func copyToolToggles(from source: URL, to target: URL) throws -> Int {
        guard let targetAccount = ClaudeDataDir(url: target).accountUuid else { throw ConfigError.targetNotSignedIn }
        guard let sourceAccount = ClaudeDataDir(url: source).accountUuid,
              let src = try? readObject(source.appendingPathComponent(togglesFile)) else {
            throw ConfigError.sourceUnreadable
        }
        let incoming = (src["owners"] as? [String: Any])?[sourceAccount] as? [String] ?? []

        let targetURL = target.appendingPathComponent(togglesFile)
        var dst: [String: Any] = ["v": src["v"] ?? 3, "owners": [String: Any]()]
        if FileManager.default.fileExists(atPath: targetURL.path) {
            guard let obj = try? readObject(targetURL) else { throw ConfigError.targetUnreadable }
            dst = obj
        }
        var owners = dst["owners"] as? [String: Any] ?? [:]
        let existing = owners[targetAccount] as? [String] ?? []
        let added = incoming.filter { !existing.contains($0) }
        guard !added.isEmpty else { return 0 }

        owners[targetAccount] = existing + added
        dst["owners"] = owners
        try write(dst, to: targetURL)
        return added.count
    }

    /// Names of plugins Claude has downloaded into this profile (they come from the account, server-side).
    public static func installedPlugins(in dataDir: URL) -> [String] {
        let root = dataDir.appendingPathComponent("local-agent-mode-sessions")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        var names = Set<String>()
        for case let url as URL in walker where url.lastPathComponent == "plugin.json"
            && url.deletingLastPathComponent().lastPathComponent == ".claude-plugin" {
            if let name = (try? readObject(url))?["name"] as? String { names.insert(name) }
        }
        return names.sorted()
    }

    /// MCP servers Claude Code reads from `~/.claude.json`; shared by every profile.
    public static func claudeCodeMCPServers(
        file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
    ) -> [String] {
        ((try? readObject(file))?["mcpServers"] as? [String: Any] ?? [:]).keys.sorted()
    }

    private static func readObject(_ url: URL) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    }

    private static func write(_ obj: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

/// What to carry from one profile's Desktop config to another.
public struct ConfigCarry: Equatable, Sendable {
    public var source: URL
    public var mcpServers: [String]
    public var toolToggles: Bool

    public init(source: URL, mcpServers: [String], toolToggles: Bool) {
        self.source = source
        self.mcpServers = mcpServers
        self.toolToggles = toolToggles
    }

    public var isEmpty: Bool { mcpServers.isEmpty && !toolToggles }

    /// Only call while Claude is not running on `target`, or it may overwrite the files.
    public func apply(to target: URL) -> ConfigApplyResult {
        var result = ConfigApplyResult()
        do {
            if !mcpServers.isEmpty {
                result.servers = try DesktopConfig.copyMCPServers(mcpServers, from: source, to: target)
            }
            if toolToggles {
                result.togglesAdded = try DesktopConfig.copyToolToggles(from: source, to: target)
            }
        } catch let error as ConfigError {
            result.failure = error
        } catch {
            Log.error("Config copy failed: \(error.localizedDescription)")
            result.failure = .targetUnreadable
        }
        return result
    }
}

public struct ConfigApplyResult: Equatable, Sendable {
    public var servers: [String: ConfigCopyOutcome]
    public var togglesAdded: Int?
    public var failure: ConfigError?

    public init(servers: [String: ConfigCopyOutcome] = [:], togglesAdded: Int? = nil, failure: ConfigError? = nil) {
        self.servers = servers
        self.togglesAdded = togglesAdded
        self.failure = failure
    }
}

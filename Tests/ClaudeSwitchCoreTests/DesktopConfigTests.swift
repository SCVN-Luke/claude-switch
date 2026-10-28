import Foundation
import Testing
@testable import ClaudeSwitchCore

private func write(_ obj: Any, _ dir: URL, _ name: String) {
    FakeDataDir.writeJSON(obj, to: dir.appendingPathComponent(name))
}

private func read(_ dir: URL, _ name: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent(name)))) as? [String: Any] ?? [:]
}

private let config = "claude_desktop_config.json"
private let toggles = "mcp-user-tool-toggles.json"

struct DesktopConfigTests {
    func source() -> URL {
        let dir = FakeDataDir.make(account: "acc1")
        write(["mcpServers": [
            "unity": ["command": "/usr/local/bin/uvx", "args": ["mcp-unity"]],
            "rea": ["command": "rea", "args": ["serve"], "env": ["TOKEN": "secret-value"]],
            "remote": ["url": "https://mcp.example.com/sse"],
        ], "preferences": ["sidebarMode": "a"]], dir, config)
        write(["v": 3, "owners": ["acc1": ["local:unity:a", "local:unity:b"]]], dir, toggles)
        return dir
    }

    @Test func listsServersWithoutSecrets() {
        let servers = DesktopConfig.mcpServers(in: source())
        #expect(servers.map(\.name) == ["rea", "remote", "unity"])
        #expect(servers.first { $0.name == "unity" }?.detail == "uvx")
        #expect(servers.first { $0.name == "remote" }?.detail == "mcp.example.com")
        #expect(!servers.map(\.detail).joined().contains("secret"))
        #expect(DesktopConfig.mcpServers(in: makeTempDir()).isEmpty)
    }

    @Test func copyMergesKeepsOtherKeysAndBacksUp() throws {
        let src = source()
        let dst = FakeDataDir.make(account: "acc2")
        write(["mcpServers": ["rea": ["command": "other"]], "preferences": ["sidebarMode": "b"]], dst, config)
        let before = try Data(contentsOf: dst.appendingPathComponent(config))

        let result = try DesktopConfig.copyMCPServers(["unity", "rea", "missing"], from: src, to: dst)
        #expect(result == ["unity": .copied, "rea": .alreadyExists, "missing": .notFound])
        let after = read(dst, config)
        let servers = after["mcpServers"] as? [String: [String: Any]]
        #expect(servers?["unity"]?["command"] as? String == "/usr/local/bin/uvx")
        #expect(servers?["rea"]?["command"] as? String == "other")
        #expect((after["preferences"] as? [String: String])?["sidebarMode"] == "b")
        #expect(try Data(contentsOf: dst.appendingPathComponent(config + ".bak")) == before)
    }

    @Test func copyCarriesEnvVerbatim() throws {
        let dst = FakeDataDir.make(account: "acc2")
        _ = try DesktopConfig.copyMCPServers(["rea"], from: source(), to: dst)
        let rea = (read(dst, config)["mcpServers"] as? [String: [String: Any]])?["rea"]
        #expect((rea?["env"] as? [String: String])?["TOKEN"] == "secret-value")
    }

    @Test func copyCreatesMissingTargetFile() throws {
        let dst = FakeDataDir.make(account: "acc2")
        #expect(try DesktopConfig.copyMCPServers(["unity"], from: source(), to: dst) == ["unity": .copied])
        #expect(DesktopConfig.mcpServers(in: dst).map(\.name) == ["unity"])
        #expect(!FileManager.default.fileExists(atPath: dst.appendingPathComponent(config + ".bak").path))
    }

    @Test func corruptTargetIsNotOverwritten() throws {
        let dst = FakeDataDir.make(account: "acc2")
        try Data("{ nope".utf8).write(to: dst.appendingPathComponent(config))
        #expect(throws: ConfigError.targetUnreadable) {
            try DesktopConfig.copyMCPServers(["unity"], from: source(), to: dst)
        }
        #expect(try String(contentsOf: dst.appendingPathComponent(config), encoding: .utf8) == "{ nope")
    }

    @Test func toolTogglesAreUnionedUnderTargetAccount() throws {
        let dst = FakeDataDir.make(account: "acc2")
        write(["v": 3, "owners": ["acc2": ["local:unity:b", "local:x:y"], "other": ["z"]]], dst, toggles)
        #expect(try DesktopConfig.copyToolToggles(from: source(), to: dst) == 1)
        let owners = read(dst, toggles)["owners"] as? [String: [String]]
        #expect(Set(owners?["acc2"] ?? []) == ["local:unity:a", "local:unity:b", "local:x:y"])
        #expect(owners?["other"] == ["z"])
        #expect(read(dst, toggles)["v"] as? Int == 3)
    }

    @Test func toolTogglesNeedSignedInTarget() {
        #expect(throws: ConfigError.targetNotSignedIn) {
            try DesktopConfig.copyToolToggles(from: source(), to: makeTempDir())
        }
    }

    @Test func listsInstalledPlugins() throws {
        let dir = makeTempDir()
        for (path, name) in [("local-agent-mode-sessions/a/o/rpm/plugin_1", "superpowers"),
                             ("local-agent-mode-sessions/skills-plugin/a/o", "anthropic-skills")] {
            let meta = dir.appendingPathComponent(path).appendingPathComponent(".claude-plugin")
            try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
            write(["name": name], meta, "plugin.json")
        }
        #expect(DesktopConfig.installedPlugins(in: dir) == ["anthropic-skills", "superpowers"])
        #expect(DesktopConfig.installedPlugins(in: makeTempDir()).isEmpty)
    }

    @Test func readsSharedClaudeCodeServers() throws {
        let file = makeTempDir().appendingPathComponent(".claude.json")
        FakeDataDir.writeJSON(["mcpServers": ["unity-mcp": ["command": "x"], "rea": ["command": "y"]], "other": 1], to: file)
        #expect(DesktopConfig.claudeCodeMCPServers(file: file) == ["rea", "unity-mcp"])
        #expect(DesktopConfig.claudeCodeMCPServers(file: makeTempDir().appendingPathComponent("none")).isEmpty)
    }
}

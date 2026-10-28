import Foundation
import Testing
@testable import ClaudeSwitchCore

struct ConfigSwitchTests {
    @Test func configIsAppliedBeforeLaunch() async throws {
        let source = FakeDataDir.make(account: "acc1")
        FakeDataDir.writeJSON(["mcpServers": ["unity": ["command": "uvx"]]],
                              to: source.appendingPathComponent("claude_desktop_config.json"))
        FakeDataDir.writeJSON(["v": 3, "owners": ["acc1": ["local:unity:a"]]],
                              to: source.appendingPathComponent("mcp-user-tool-toggles.json"))
        let root = makeTempDir()
        let target = try ProfileStore(root: root).addProfile(name: "B")
        let targetDir = URL(fileURLWithPath: target.dataDir!)
        FakeDataDir.writeJSON(["lastKnownAccountUuid": "acc2"], to: targetDir.appendingPathComponent("config.json"))

        let claude = FakeClaude()
        let seenAtLaunch = Flag()
        await claude.set(onLaunch: { seenAtLaunch.value = !DesktopConfig.mcpServers(in: targetDir).isEmpty })
        let c = SwitchCoordinator(claude: claude, store: ProfileStore(root: root),
                                  cookies: FakeCookies(result: .failure(.notFound)), defaultDir: source)
        let carry = ConfigCarry(source: source, mcpServers: ["unity"], toolToggles: true)
        let step = await c.switchTo(target, carrying: [], config: carry, force: false)

        #expect(step == .done(transfer: [:], config: ConfigApplyResult(servers: ["unity": .copied], togglesAdded: 1)))
        #expect(seenAtLaunch.value)
    }

    @Test func configErrorDoesNotBlockLaunch() async throws {
        let root = makeTempDir()
        let target = try ProfileStore(root: root).addProfile(name: "Fresh")
        let claude = FakeClaude()
        let c = SwitchCoordinator(claude: claude, store: ProfileStore(root: root),
                                  cookies: FakeCookies(result: .failure(.notFound)), defaultDir: makeTempDir())
        let carry = ConfigCarry(source: makeTempDir(), mcpServers: ["x"], toolToggles: false)
        let step = await c.switchTo(target, carrying: [], config: carry, force: false)
        #expect(step == .done(transfer: [:], config: ConfigApplyResult(failure: .sourceUnreadable)))
        #expect(await claude.calls.last == "launch:\(target.dataDir!)")
    }

    @Test func applyNowWithoutSwitch() throws {
        let source = FakeDataDir.make(account: "acc1")
        FakeDataDir.writeJSON(["mcpServers": ["unity": ["command": "uvx"]]],
                              to: source.appendingPathComponent("claude_desktop_config.json"))
        let target = FakeDataDir.make(account: "acc2")
        let r = ConfigCarry(source: source, mcpServers: ["unity"], toolToggles: false).apply(to: target)
        #expect(r == ConfigApplyResult(servers: ["unity": .copied]))
    }
}

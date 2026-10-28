import Foundation
import Testing
@testable import ClaudeSwitchCore

actor FakeClaude: ClaudeControlling {
    var calls: [String] = []
    var running: URL?? = .some(nil)
    var quitResult: QuitResult = .quit
    /// Set by tests to observe the filesystem at launch time.
    var onLaunch: (@Sendable () -> Void)?

    func set(quitResult: QuitResult) { self.quitResult = quitResult }
    func set(onLaunch: @escaping @Sendable () -> Void) { self.onLaunch = onLaunch }

    func runningDataDir() async -> URL?? { running }
    func quit(timeout: TimeInterval) async -> QuitResult {
        calls.append("quit")
        if quitResult == .quit { running = nil }
        return quitResult
    }
    func forceQuit() async { calls.append("forceQuit"); running = nil }
    func launch(dataDir: URL?) async throws {
        onLaunch?()
        calls.append("launch:\(dataDir?.path ?? "default")")
    }
}

final class Flag: @unchecked Sendable { var value = false }

struct SwitchCoordinatorTests {
    let defaultDir = FakeDataDir.make(account: "acc1", sessions: ["org1": [FakeDataDir.session("s1")]])
    let storeRoot = makeTempDir()

    func make(_ claude: FakeClaude, cookies: CookieSource = FakeCookies(result: .failure(.notFound))) -> SwitchCoordinator {
        SwitchCoordinator(claude: claude, store: ProfileStore(root: storeRoot), cookies: cookies, defaultDir: defaultDir)
    }

    /// Profile 2 with a logged-in data dir (account acc2, org folder org2).
    func loggedInTarget() throws -> Profile {
        let p = try ProfileStore(root: storeRoot).addProfile(name: "Account 2")
        let dir = URL(fileURLWithPath: p.dataDir!)
        FakeDataDir.writeJSON(["lastKnownAccountUuid": "acc2"], to: dir.appendingPathComponent("config.json"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("claude-code-sessions/acc2/org2"),
                                                withIntermediateDirectories: true)
        return p
    }

    @Test func orderQuitTransferLaunch() async throws {
        let claude = FakeClaude()
        let target = try loggedInTarget()
        let copiedBeforeLaunch = Flag()
        let dest = URL(fileURLWithPath: target.dataDir!).appendingPathComponent("claude-code-sessions/acc2/org2/local_s1.json")
        await claude.set(onLaunch: { copiedBeforeLaunch.value = FileManager.default.fileExists(atPath: dest.path) })

        let sessions = ClaudeDataDir(url: defaultDir).sessions()
        let step = await make(claude).switchTo(target, carrying: sessions, force: false)

        #expect(step == .done(transfer: ["s1": .copied]))
        #expect(await claude.calls == ["quit", "launch:\(target.dataDir!)"])
        #expect(copiedBeforeLaunch.value)
        #expect(try ProfileStore(root: storeRoot).load().activeProfileId == target.id)
    }

    @Test func stillRunningAsksForce() async throws {
        let claude = FakeClaude()
        await claude.set(quitResult: .stillRunning)
        let target = try loggedInTarget()
        let sessions = ClaudeDataDir(url: defaultDir).sessions()
        let coordinator = make(claude)

        #expect(await coordinator.switchTo(target, carrying: sessions, force: false) == .needsForceQuit)
        #expect(await claude.calls == ["quit"])
        let dest = URL(fileURLWithPath: target.dataDir!).appendingPathComponent("claude-code-sessions/acc2/org2/local_s1.json")
        #expect(!FileManager.default.fileExists(atPath: dest.path))

        let step = await coordinator.switchTo(target, carrying: sessions, force: true)
        #expect(step == .done(transfer: ["s1": .copied]))
        #expect(await claude.calls == ["quit", "quit", "forceQuit", "launch:\(target.dataDir!)"])
    }

    @Test func transferErrorStillLaunches() async throws {
        let claude = FakeClaude()
        let target = try ProfileStore(root: storeRoot).addProfile(name: "Fresh")
        let step = await make(claude).switchTo(target, carrying: ClaudeDataDir(url: defaultDir).sessions(), force: false)
        #expect(step == .done(transfer: ["s1": .failed("Hãy mở profile này và đăng nhập một lần trước")]))
        #expect(await claude.calls.last == "launch:\(target.dataDir!)")
    }

    @Test func defaultProfileLaunchesWithoutFlag() async throws {
        let claude = FakeClaude()
        let def = try ProfileStore(root: storeRoot).load().profiles[0]
        _ = await make(claude).switchTo(def, carrying: [], force: false)
        #expect(await claude.calls.last == "launch:default")
    }

    @Test func notRunningSkipsQuit() async throws {
        let claude = FakeClaude()
        await claude.set(quitResult: .notRunning)
        let target = try loggedInTarget()
        #expect(await make(claude).switchTo(target, carrying: [], force: false) == .done(transfer: [:]))
    }
}

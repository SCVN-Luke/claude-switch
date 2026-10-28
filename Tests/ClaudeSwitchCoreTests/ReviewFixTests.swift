import Foundation
import Testing
@testable import ClaudeSwitchCore

struct ReviewFixTests {
    @Test func unreadableProfilesFileIsNotOverwritten() throws {
        let root = makeTempDir()
        let file = root.appendingPathComponent("profiles.json")
        try Data(#"{"profiles":[]}"#.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }
        #expect(throws: (any Error).self) { try ProfileStore(root: root).load() }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(try String(contentsOf: file, encoding: .utf8) == #"{"profiles":[]}"#)
    }

    @Test func cannotDeleteDataOfRunningProfile() throws {
        let store = ProfileStore(root: makeTempDir())
        let p = try store.addProfile(name: "A")
        #expect(throws: ProfileError.profileIsRunning) {
            try store.remove(id: p.id, deleteData: true, isRunning: true)
        }
        #expect(FileManager.default.fileExists(atPath: p.dataDir!))
        #expect(try store.load().profiles.count == 2)
    }

    @Test func usageRequestsNeverStoreOrSendCookieJar() async throws {
        let rec = Recorder()
        _ = try await stubClient(recorder: rec).fetch(org: "o", sessionKey: "k")
        #expect(rec.requests.first?.httpShouldHandleCookies == false)
        let cfg = UsageClient.sessionConfiguration
        #expect(cfg.httpCookieStorage == nil)
        #expect(cfg.httpShouldSetCookies == false)
        #expect(cfg.urlCache == nil)
    }

    @Test func concurrentSwitchIsRejected() async throws {
        let claude = SlowClaude()
        let root = makeTempDir()
        let store = ProfileStore(root: root)
        let target = try store.addProfile(name: "B")
        let c = SwitchCoordinator(claude: claude, store: store, cookies: FakeCookies(result: .failure(.notFound)),
                                  defaultDir: makeTempDir())
        async let first = c.switchTo(target, carrying: [], force: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        let second = await c.switchTo(target, carrying: [], force: false)
        #expect(second == .failed(SwitchCoordinator.busyMessage))
        #expect(await first == .done(transfer: [:]))
        #expect(await claude.launches == 1)
    }

    @Test func missingClaudeAppGivesClearMessage() async throws {
        let claude = FakeClaude()
        await claude.set(launchError: LaunchError.claudeNotFound)
        let store = ProfileStore(root: makeTempDir())
        let target = try store.addProfile(name: "B")
        let c = SwitchCoordinator(claude: claude, store: store, cookies: FakeCookies(), defaultDir: makeTempDir())
        #expect(await c.switchTo(target, carrying: [], force: false) == .failed(SwitchCoordinator.claudeMissingMessage))
    }
}

actor SlowClaude: ClaudeControlling {
    var launches = 0
    func runningDataDir() async -> URL?? { nil }
    func quit(timeout: TimeInterval) async -> QuitResult {
        try? await Task.sleep(nanoseconds: 200_000_000)
        return .notRunning
    }
    func forceQuit() async {}
    func launch(dataDir: URL?) async throws { launches += 1 }
}


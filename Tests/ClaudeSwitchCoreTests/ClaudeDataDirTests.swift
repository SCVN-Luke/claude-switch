import Foundation
import Testing
@testable import ClaudeSwitchCore

struct ClaudeDataDirTests {
    @Test func accountFromConfig() {
        #expect(ClaudeDataDir(url: FakeDataDir.make(account: "acc1")).accountUuid == "acc1")
        #expect(ClaudeDataDir(url: makeTempDir()).accountUuid == nil)
    }

    @Test func orgPrefersCookie() {
        let d = ClaudeDataDir(url: FakeDataDir.make(account: "a", orgs: ["o1"]))
        #expect(d.orgUuid(cookieOrg: "orgX") == "orgX")
    }

    @Test func orgSingleFolder() {
        #expect(ClaudeDataDir(url: FakeDataDir.make(account: "a", orgs: ["o1"])).orgUuid(cookieOrg: nil) == "o1")
        let two = FakeDataDir.make(account: "a", orgs: ["o1", "o2"],
                                   usageSamples: [["t": 1, "org": "o1", "u": [:]], ["t": 2, "org": "o2", "u": [:]]])
        #expect(ClaudeDataDir(url: two).orgUuid(cookieOrg: nil) == "o2")
        let ambiguous = FakeDataDir.make(account: "a", orgs: ["o1", "o2"])
        #expect(ClaudeDataDir(url: ambiguous).orgUuid(cookieOrg: nil) == nil)
    }

    @Test func sessionsParsesAndSkipsBroken() throws {
        let dir = FakeDataDir.make(account: "a", sessions: ["o1": [
            FakeDataDir.session("s1", title: "Old", lastActivityMs: 1_000),
            FakeDataDir.session("s2", title: "New", cwd: "/w", lastActivityMs: 2_000, archived: true),
        ]])
        try Data("not json".utf8).write(to: dir.appendingPathComponent("claude-code-sessions/a/o1/local_bad.json"))
        let s = ClaudeDataDir(url: dir).sessions()
        #expect(s.map(\.id) == ["s2", "s1"])
        #expect(s[0].title == "New" && s[0].cwd == "/w" && s[0].isArchived)
        #expect(s[0].lastActivityAt == Date(timeIntervalSince1970: 2))
        #expect(s[0].fileURL.lastPathComponent == "local_s2.json")
    }

    @Test func snapshotUsageLatestForOrg() {
        let dir = FakeDataDir.make(account: "a", orgs: ["o1"], usageSamples: [
            ["t": 1000, "org": "o1", "u": ["fh": 10, "sd": 20]],
            ["t": 2000, "org": "o1", "u": ["fh": 48, "sd": 33, "xu": 26.275]],
            ["t": 3000, "org": "o2", "u": ["fh": 99]],
        ])
        let u = ClaudeDataDir(url: dir).snapshotUsage(org: "o1")
        #expect(u?.fiveHourPct == 48)
        #expect(u?.weeklyPct == 33)
        #expect(u?.extraPct == 26.275)
        #expect(u?.fetchedAt == Date(timeIntervalSince1970: 2))
        #expect(u?.source == .file)
    }

    @Test func notLoggedInDir() {
        let d = ClaudeDataDir(url: makeTempDir())
        #expect(d.accountUuid == nil)
        #expect(d.sessions().isEmpty)
        #expect(d.snapshotUsage(org: nil) == nil)
        #expect(d.sessionsDir(org: "o") == nil)
    }
}

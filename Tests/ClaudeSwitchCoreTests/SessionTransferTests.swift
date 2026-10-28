import Foundation
import Testing
@testable import ClaudeSwitchCore

struct SessionTransferTests {
    let source = ClaudeDataDir(url: FakeDataDir.make(account: "acc1", sessions: ["org1": [
        FakeDataDir.session("s1", lastActivityMs: 2_000), FakeDataDir.session("s2", lastActivityMs: 1_000),
    ]]))

    @Test func copiesIntoTargetOrgFolder() throws {
        let target = ClaudeDataDir(url: FakeDataDir.make(account: "acc2"))
        let s1 = source.sessions().first { $0.id == "s1" }!
        let result = try SessionTransfer.transfer([s1], to: target, targetOrg: "org2")
        #expect(result == ["s1": .copied])
        let dest = target.url.appendingPathComponent("claude-code-sessions/acc2/org2/local_s1.json")
        #expect(try Data(contentsOf: dest) == Data(contentsOf: s1.fileURL))
        #expect(FileManager.default.fileExists(atPath: s1.fileURL.path))
    }

    @Test func skipsExisting() throws {
        let target = ClaudeDataDir(url: FakeDataDir.make(account: "acc2", sessions: ["org2": [
            FakeDataDir.session("s1", title: "Already here"),
        ]]))
        let dest = target.url.appendingPathComponent("claude-code-sessions/acc2/org2/local_s1.json")
        let before = try Data(contentsOf: dest)
        let result = try SessionTransfer.transfer(source.sessions(), to: target, targetOrg: "org2")
        #expect(result == ["s1": .alreadyExists, "s2": .copied])
        #expect(try Data(contentsOf: dest) == before)
    }

    @Test func targetNotLoggedInThrows() throws {
        let empty = makeTempDir()
        #expect(throws: TransferError.targetNotLoggedIn) {
            try SessionTransfer.transfer(source.sessions(), to: ClaudeDataDir(url: empty), targetOrg: "org2")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: empty.path).isEmpty)
    }

    @Test func targetWithoutOrgThrows() {
        #expect(throws: TransferError.targetNotLoggedIn) {
            try SessionTransfer.transfer(source.sessions(), to: ClaudeDataDir(url: FakeDataDir.make(account: "acc2")),
                                         targetOrg: nil)
        }
    }
}

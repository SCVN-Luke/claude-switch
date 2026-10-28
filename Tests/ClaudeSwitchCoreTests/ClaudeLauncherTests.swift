import Foundation
import Testing
@testable import ClaudeSwitchCore

struct ClaudeLauncherTests {
    @Test func parseUserDataDirWithSpaces() {
        let p = "/Users/x/Library/Application Support/ClaudeSwitch/Profiles/A"
        #expect(ProcessArgs.userDataDir(from: ["/App/Claude", "--user-data-dir=\(p)"])?.path == p)
        #expect(ProcessArgs.userDataDir(from: ["/App/Claude", "--foo"]) == nil)
        #expect(ProcessArgs.userDataDir(from: ["/App/Claude", "--user-data-dir", "/p"])?.path == "/p")
    }

    @Test func argumentsOfSelf() throws {
        let args = try #require(ProcessArgs.arguments(pid: getpid()))
        #expect(args.first?.contains("ClaudeSwitchCoreTests") == true)
        #expect(args == CommandLine.arguments)
    }

    @Test func matchProfileStandardizes() {
        let def = Profile(name: "Default", dataDir: nil)
        let other = Profile(name: "B", dataDir: "/a/b")
        let defaultDir = URL(fileURLWithPath: "/claude-default")
        let all = [def, other]
        #expect(matchProfile(.some(URL(fileURLWithPath: "/a/b/")), in: all, defaultDir: defaultDir) == other)
        #expect(matchProfile(.some(URL(fileURLWithPath: "/a/./b")), in: all, defaultDir: defaultDir) == other)
        #expect(matchProfile(.some(nil), in: all, defaultDir: defaultDir) == def)
        #expect(matchProfile(.some(URL(fileURLWithPath: "/claude-default")), in: all, defaultDir: defaultDir) == def)
        #expect(matchProfile(nil, in: all, defaultDir: defaultDir) == nil)
        #expect(matchProfile(.some(URL(fileURLWithPath: "/unknown")), in: all, defaultDir: defaultDir) == nil)
    }

    @Test func launchArgumentsForProfile() {
        #expect(ClaudeLauncher.launchArguments(dataDir: nil) == [])
        let p = URL(fileURLWithPath: "/x/Application Support/P")
        #expect(ClaudeLauncher.launchArguments(dataDir: p) == ["--user-data-dir=/x/Application Support/P"])
    }
}

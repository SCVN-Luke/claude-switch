import Foundation
import Testing
@testable import ClaudeSwitchCore

struct ProfileStoreTests {
    let root = makeTempDir()
    var store: ProfileStore { ProfileStore(root: root) }
    var fm: FileManager { .default }

    @Test func firstLoadCreatesDefaultProfile() throws {
        let file = try store.load()
        #expect(file.profiles.count == 1)
        #expect(file.profiles[0].name == "Account 1")
        #expect(file.profiles[0].dataDir == nil)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("profiles.json").path))
    }

    @Test func addProfileCreatesDataDir() throws {
        let p = try store.addProfile(name: "Account 2")
        let expected = root.appendingPathComponent("Profiles/\(p.id.uuidString)").path
        #expect(p.dataDir == expected)
        var isDir: ObjCBool = false
        #expect(fm.fileExists(atPath: expected, isDirectory: &isDir) && isDir.boolValue)
        #expect(try store.load().profiles.count == 2)
    }

    @Test func removeDefaultThrows() throws {
        let def = try store.load().profiles[0]
        #expect(throws: ProfileError.cannotRemoveDefault) {
            try store.remove(id: def.id, deleteData: false)
        }
    }

    @Test func removeKeepsDataByDefault() throws {
        let a = try store.addProfile(name: "A")
        try store.remove(id: a.id, deleteData: false)
        #expect(fm.fileExists(atPath: a.dataDir!))
        #expect(try store.load().profiles.count == 1)

        let b = try store.addProfile(name: "B")
        try store.remove(id: b.id, deleteData: true)
        #expect(!fm.fileExists(atPath: b.dataDir!))
    }

    @Test func renamePersists() throws {
        let a = try store.addProfile(name: "A")
        try store.rename(id: a.id, to: "Work")
        #expect(try store.load().profiles.first { $0.id == a.id }?.name == "Work")
    }

    @Test func setActivePersists() throws {
        let a = try store.addProfile(name: "A")
        try store.setActive(a.id)
        #expect(try store.load().activeProfileId == a.id)
    }

    @Test func resolvedDataDirUsesDefaultWhenNil() throws {
        let def = try store.load().profiles[0]
        let d = URL(fileURLWithPath: "/tmp/claude-default")
        #expect(def.resolvedDataDir(defaultDir: d) == d)
    }
}

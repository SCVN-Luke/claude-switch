import Foundation
import SQLite3
import Testing
@testable import ClaudeSwitchCore

struct FakePasswords: SafeStoragePasswordProvider {
    var value = Data("test-password".utf8)
    func password() throws -> Data { value }
}

/// Writes a minimal Chromium-style `Cookies` DB into `dir`.
func makeCookieDB(in dir: URL, cookies: [(host: String, name: String, value: String)], version: Int = 24,
                  password: Data = FakePasswords().value) {
    let key = CookieCrypto.deriveKey(password: password)
    var db: OpaquePointer?
    sqlite3_open(dir.appendingPathComponent("Cookies").path, &db)
    defer { sqlite3_close(db) }
    sqlite3_exec(db, "CREATE TABLE meta(key TEXT, value TEXT); CREATE TABLE cookies(host_key TEXT, name TEXT, encrypted_value BLOB);", nil, nil, nil)
    sqlite3_exec(db, "INSERT INTO meta VALUES('version','\(version)')", nil, nil, nil)
    for c in cookies {
        let blob = CookieCrypto.encrypt(c.value, key: key, hostKey: c.host, metaVersion: version)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO cookies VALUES(?,?,?)", -1, &stmt, nil)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, c.host, -1, transient)
        sqlite3_bind_text(stmt, 2, c.name, -1, transient)
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(blob.count), transient) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }
}

struct CookieReaderTests {
    let key = CookieCrypto.deriveKey(password: FakePasswords().value)

    @Test func roundTripV24() throws {
        let blob = CookieCrypto.encrypt("sk-ant-abc", key: key, hostKey: ".claude.ai", metaVersion: 24)
        #expect(try CookieCrypto.decrypt(blob, key: key, hostKey: ".claude.ai", metaVersion: 24) == "sk-ant-abc")
        let old = CookieCrypto.encrypt("sk-ant-abc", key: key, hostKey: ".claude.ai", metaVersion: 23)
        #expect(try CookieCrypto.decrypt(old, key: key, hostKey: ".claude.ai", metaVersion: 23) == "sk-ant-abc")
    }

    @Test func hostHashMismatchThrows() {
        let blob = CookieCrypto.encrypt("x", key: key, hostKey: ".claude.ai", metaVersion: 24)
        #expect(throws: CookieError.decryptFailed) {
            try CookieCrypto.decrypt(blob, key: key, hostKey: "claude.ai", metaVersion: 24)
        }
    }

    @Test func missingV10PrefixThrows() {
        #expect(throws: CookieError.badFormat) {
            try CookieCrypto.decrypt(Data("plain".utf8), key: key, hostKey: ".claude.ai", metaVersion: 24)
        }
    }

    @Test func readsFromCopyOfDb() throws {
        let dir = makeTempDir()
        makeCookieDB(in: dir, cookies: [(".claude.ai", "sessionKey", "sk-1"), (".claude.ai", "lastActiveOrg", "org-1"),
                                        (".example.com", "sessionKey", "other")])
        var locker: OpaquePointer?
        sqlite3_open(dir.appendingPathComponent("Cookies").path, &locker)
        sqlite3_exec(locker, "BEGIN EXCLUSIVE", nil, nil, nil)
        defer { sqlite3_exec(locker, "ROLLBACK", nil, nil, nil); sqlite3_close(locker) }

        let c = try CookieReader(passwords: FakePasswords()).read(dataDir: dir)
        #expect(c.sessionKey == "sk-1")
        #expect(c.lastActiveOrg == "org-1")
    }

    @Test func noSessionKeyThrowsNotFound() {
        let dir = makeTempDir()
        makeCookieDB(in: dir, cookies: [(".claude.ai", "lastActiveOrg", "org-1")])
        #expect(throws: CookieError.notFound) {
            try CookieReader(passwords: FakePasswords()).read(dataDir: dir)
        }
    }

    @Test func noCookieFileThrowsNotFound() {
        #expect(throws: CookieError.notFound) {
            try CookieReader(passwords: FakePasswords()).read(dataDir: makeTempDir())
        }
    }
}

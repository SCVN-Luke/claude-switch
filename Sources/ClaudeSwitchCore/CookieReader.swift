import CommonCrypto
import CryptoKit
import Foundation
import Security
import SQLite3

public enum CookieError: Error, Equatable {
    case notFound, badFormat, decryptFailed, keychain(OSStatus), dbOpenFailed
}

public struct ClaudeCookies: Equatable, Sendable {
    public var sessionKey: String
    public var lastActiveOrg: String?
}

public protocol SafeStoragePasswordProvider: Sendable {
    func password() throws -> Data
}

/// Something that can read the claude.ai cookies of a data dir (fakeable in tests).
public protocol CookieSource: Sendable {
    func read(dataDir: URL) throws -> ClaudeCookies
}

/// Reads the "Claude Safe Storage" Keychain item once and keeps it in memory only.
public final class KeychainPasswordProvider: SafeStoragePasswordProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var cached: Data?

    public init() {}

    public func password() throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { throw CookieError.keychain(status) }
        cached = data
        return data
    }
}

/// Chromium-on-macOS cookie encryption: "v10" + AES-128-CBC, IV of 16 spaces, key from
/// PBKDF2-HMAC-SHA1(password, "saltysalt", 1003 rounds). DB version >= 24 prefixes the
/// plaintext with SHA-256(host_key).
public enum CookieCrypto {
    static let iv = Data(repeating: 0x20, count: 16)

    public static func deriveKey(password: Data) -> Data {
        var key = Data(count: 16)
        let salt = Array("saltysalt".utf8)
        _ = key.withUnsafeMutableBytes { keyPtr in
            password.withUnsafeBytes { pwPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwPtr.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                    salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), 16)
            }
        }
        return key
    }

    public static func decrypt(_ blob: Data, key: Data, hostKey: String, metaVersion: Int) throws -> String {
        guard blob.starts(with: Array("v10".utf8)) else { throw CookieError.badFormat }
        guard var plain = aes(CCOperation(kCCDecrypt), Data(blob.dropFirst(3)), key: key) else {
            throw CookieError.decryptFailed
        }
        if metaVersion >= 24 {
            guard plain.starts(with: Data(SHA256.hash(data: Data(hostKey.utf8)))) else {
                throw CookieError.decryptFailed
            }
            plain = plain.dropFirst(32)
        }
        guard let s = String(data: plain, encoding: .utf8) else { throw CookieError.decryptFailed }
        return s
    }

    /// Inverse of `decrypt`; used by tests to build fixtures.
    public static func encrypt(_ plain: String, key: Data, hostKey: String, metaVersion: Int) -> Data {
        var data = Data(plain.utf8)
        if metaVersion >= 24 { data = Data(SHA256.hash(data: Data(hostKey.utf8))) + data }
        return Data("v10".utf8) + (aes(CCOperation(kCCEncrypt), data, key: key) ?? Data())
    }

    private static func aes(_ op: CCOperation, _ input: Data, key: Data) -> Data? {
        var out = Data(count: input.count + kCCBlockSizeAES128)
        let capacity = out.count
        var outLen = 0
        let rc = out.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                keyPtr.baseAddress, key.count, ivPtr.baseAddress,
                                inPtr.baseAddress, input.count, outPtr.baseAddress, capacity, &outLen)
                    }
                }
            }
        }
        return rc == kCCSuccess ? out.prefix(outLen) : nil
    }
}

/// Reads claude.ai cookies from a temp copy of `<dataDir>/Cookies`, so a running Claude's
/// lock never gets in the way. Values are returned in memory only.
public struct CookieReader: CookieSource {
    let passwords: SafeStoragePasswordProvider

    public init(passwords: SafeStoragePasswordProvider) {
        self.passwords = passwords
    }

    public func read(dataDir: URL) throws -> ClaudeCookies {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dataDir.appendingPathComponent("Cookies").path) else { throw CookieError.notFound }
        let tmp = fm.temporaryDirectory.appendingPathComponent("claudeswitch-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for name in ["Cookies", "Cookies-journal", "Cookies-wal"] {
            let src = dataDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: tmp.appendingPathComponent(name)) }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.appendingPathComponent("Cookies").path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK
        else { sqlite3_close(db); throw CookieError.dbOpenFailed }
        defer { sqlite3_close(db) }

        var version = 0
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW, let v = sqlite3_column_text(stmt, 0) {
            version = Int(String(cString: v)) ?? 0
        }
        sqlite3_finalize(stmt)

        var rows: [String: (host: String, blob: Data)] = [:]
        let sql = "SELECT name, host_key, encrypted_value FROM cookies WHERE host_key IN ('.claude.ai','claude.ai') AND name IN ('sessionKey','lastActiveOrg')"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CookieError.dbOpenFailed }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let host = String(cString: sqlite3_column_text(stmt, 1))
            let len = Int(sqlite3_column_bytes(stmt, 2))
            let blob = len > 0 ? Data(bytes: sqlite3_column_blob(stmt, 2), count: len) : Data()
            rows[name] = (host, blob)
        }
        sqlite3_finalize(stmt)

        guard let sk = rows["sessionKey"] else { throw CookieError.notFound }
        let key = CookieCrypto.deriveKey(password: try passwords.password())
        let sessionKey = try CookieCrypto.decrypt(sk.blob, key: key, hostKey: sk.host, metaVersion: version)
        let org = rows["lastActiveOrg"].flatMap {
            try? CookieCrypto.decrypt($0.blob, key: key, hostKey: $0.host, metaVersion: version)
        }
        return ClaudeCookies(sessionKey: sessionKey, lastActiveOrg: org)
    }
}

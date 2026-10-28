// Spike S2 (throwaway): read the claude.ai sessionKey cookie of a Claude Desktop data dir,
// call the usage API, and print only the usage numbers. The cookie is never printed.
//
// Usage: swift scripts/spike-usage.swift [dataDir]
//   dataDir defaults to ~/Library/Application Support/Claude

import CommonCrypto
import CryptoKit
import Foundation
import Security
import SQLite3

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

let dataDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude")

// 1. Keychain password (macOS shows an access prompt the first time).
func safeStoragePassword() -> Data {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Safe Storage",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var out: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &out)
    guard status == errSecSuccess, let data = out as? Data else {
        fail("Keychain read failed: \(status)")
    }
    return data
}

// 2. Chromium macOS cookie decryption.
func deriveKey(_ password: Data) -> Data {
    var key = Data(count: 16)
    let salt = Array("saltysalt".utf8)
    let rc = key.withUnsafeMutableBytes { keyPtr in
        password.withUnsafeBytes { pwPtr in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pwPtr.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                keyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), 16)
        }
    }
    guard rc == kCCSuccess else { fail("PBKDF2 failed: \(rc)") }
    return key
}

func decrypt(_ blob: Data, key: Data, hostKey: String, metaVersion: Int) -> String {
    guard blob.starts(with: Array("v10".utf8)) else { fail("Unexpected cookie prefix") }
    let cipher = blob.dropFirst(3)
    let iv = Data(repeating: 0x20, count: 16)
    var out = Data(count: cipher.count + kCCBlockSizeAES128)
    var outLen = 0
    let outCapacity = out.count
    let rc = out.withUnsafeMutableBytes { outPtr in
        cipher.withUnsafeBytes { inPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    CCCrypt(
                        CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyPtr.baseAddress, 16, ivPtr.baseAddress,
                        inPtr.baseAddress, cipher.count,
                        outPtr.baseAddress, outCapacity, &outLen)
                }
            }
        }
    }
    guard rc == kCCSuccess else { fail("AES decrypt failed: \(rc)") }
    var plain = out.prefix(outLen)
    if metaVersion >= 24 {
        let hostHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
        guard plain.starts(with: hostHash) else { fail("Host hash mismatch") }
        plain = plain.dropFirst(32)
    }
    guard let s = String(data: plain, encoding: .utf8) else { fail("Cookie not UTF-8") }
    return s
}

// 3. Read cookies from a temp copy of the SQLite DB.
func readCookies(names: [String]) -> [String: (host: String, blob: Data)] {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("cs-spike-\(UUID().uuidString)")
    try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    for f in ["Cookies", "Cookies-journal"] {
        let src = dataDir.appendingPathComponent(f)
        if fm.fileExists(atPath: src.path) {
            try? fm.copyItem(at: src, to: tmp.appendingPathComponent(f))
        }
    }
    var db: OpaquePointer?
    guard sqlite3_open_v2(tmp.appendingPathComponent("Cookies").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK
    else { fail("Cannot open Cookies DB") }
    defer { sqlite3_close(db) }

    var result: [String: (String, Data)] = [:]
    var stmt: OpaquePointer?
    let sql = "SELECT name, host_key, encrypted_value FROM cookies WHERE host_key IN ('.claude.ai','claude.ai')"
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    while sqlite3_step(stmt) == SQLITE_ROW {
        let name = String(cString: sqlite3_column_text(stmt, 0))
        guard names.contains(name) else { continue }
        let host = String(cString: sqlite3_column_text(stmt, 1))
        let len = Int(sqlite3_column_bytes(stmt, 2))
        let blob = Data(bytes: sqlite3_column_blob(stmt, 2), count: len)
        result[name] = (host, blob)
    }
    sqlite3_finalize(stmt)

    sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key='version'", -1, &stmt, nil)
    if sqlite3_step(stmt) == SQLITE_ROW {
        metaVersion = Int(String(cString: sqlite3_column_text(stmt, 0))) ?? 0
    }
    sqlite3_finalize(stmt)
    return result
}

var metaVersion = 0
let cookies = readCookies(names: ["sessionKey", "lastActiveOrg"])
guard let sk = cookies["sessionKey"] else { fail("No sessionKey cookie — profile not logged in?") }
let key = deriveKey(safeStoragePassword())
let sessionKey = decrypt(sk.blob, key: key, hostKey: sk.host, metaVersion: metaVersion)
guard let org = cookies["lastActiveOrg"].map({ decrypt($0.blob, key: key, hostKey: $0.host, metaVersion: metaVersion) })
else { fail("No lastActiveOrg cookie") }
print("data dir: \(dataDir.path)")
print("org: \(org.prefix(8))…  (sessionKey decrypted, \(sessionKey.count) chars, not shown)")

// 4. Call the usage API.
var req = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(org)/usage")!)
req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
req.setValue("application/json", forHTTPHeaderField: "Accept")
req.setValue(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Claude/4.29.0 Chrome/138.0.0.0 Electron/37.0.0 Safari/537.36",
    forHTTPHeaderField: "User-Agent")
req.timeoutInterval = 15

let sem = DispatchSemaphore(value: 0)
URLSession.shared.dataTask(with: req) { data, resp, err in
    defer { sem.signal() }
    if let err { print("request error: \(err.localizedDescription)"); return }
    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
    print("HTTP \(code)")
    guard code == 200, let data,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        print("body (first 200 chars): \(String(data: (data ?? Data()).prefix(200), encoding: .utf8) ?? "")")
        return
    }
    for k in ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet"] {
        if let v = json[k] as? [String: Any] {
            print("\(k): \(v["utilization"] ?? "nil")%  resets_at=\(v["resets_at"] ?? "nil")")
        }
    }
    if let x = json["extra_usage"] as? [String: Any] { print("extra_usage: \(x)") }
    print("top-level keys: \(json.keys.sorted())")
}.resume()
sem.wait()

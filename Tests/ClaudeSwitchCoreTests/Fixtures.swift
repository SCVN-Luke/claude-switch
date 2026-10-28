import Foundation

func makeTempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cs-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Builds a fake Claude Desktop data dir.
enum FakeDataDir {
    static func make(
        account: String?,
        orgs: [String] = [],
        sessions: [String: [[String: Any]]] = [:],
        usageSamples: [[String: Any]] = []
    ) -> URL {
        let dir = makeTempDir()
        let fm = FileManager.default
        if let account {
            writeJSON(["lastKnownAccountUuid": account], to: dir.appendingPathComponent("config.json"))
            for org in Set(orgs).union(sessions.keys) {
                let orgDir = dir.appendingPathComponent("claude-code-sessions/\(account)/\(org)")
                try! fm.createDirectory(at: orgDir, withIntermediateDirectories: true)
                for s in sessions[org] ?? [] {
                    writeJSON(s, to: orgDir.appendingPathComponent("local_\(s["sessionId"] as! String).json"))
                }
            }
        }
        if !usageSamples.isEmpty {
            writeJSON(["version": 2, "samples": usageSamples], to: dir.appendingPathComponent("plan-usage-history.json"))
        }
        return dir
    }

    static func session(_ id: String, title: String = "T", cwd: String = "/tmp", lastActivityMs: Double = 0,
                        archived: Bool = false) -> [String: Any] {
        ["sessionId": id, "title": title, "cwd": cwd, "lastActivityAt": lastActivityMs, "isArchived": archived,
         "cliSessionId": "cli-\(id)"]
    }

    static func writeJSON(_ obj: Any, to url: URL) {
        try! JSONSerialization.data(withJSONObject: obj).write(to: url)
    }
}

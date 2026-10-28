import Foundation

public struct SessionInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: String  // sessionId
    public var title: String
    public var cwd: String
    public var lastActivityAt: Date?
    public var isArchived: Bool
    public var fileURL: URL

    public init(id: String, title: String, cwd: String, lastActivityAt: Date?, isArchived: Bool, fileURL: URL) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.lastActivityAt = lastActivityAt
        self.isArchived = isArchived
        self.fileURL = fileURL
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public enum Source: Sendable { case live, file }
    public var fiveHourPct: Double?
    public var fiveHourResetsAt: Date?
    public var weeklyPct: Double?
    public var weeklyResetsAt: Date?
    public var extraPct: Double?
    public var fetchedAt: Date
    public var source: Source

    public init(fiveHourPct: Double?, fiveHourResetsAt: Date? = nil, weeklyPct: Double?,
                weeklyResetsAt: Date? = nil, extraPct: Double? = nil, fetchedAt: Date, source: Source) {
        self.fiveHourPct = fiveHourPct
        self.fiveHourResetsAt = fiveHourResetsAt
        self.weeklyPct = weeklyPct
        self.weeklyResetsAt = weeklyResetsAt
        self.extraPct = extraPct
        self.fetchedAt = fetchedAt
        self.source = source
    }
}

/// Read-only view of one Claude Desktop data dir. Unknown keys and broken files are ignored.
public struct ClaudeDataDir: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public var accountUuid: String? {
        (readJSON(url.appendingPathComponent("config.json")) as? [String: Any])?["lastKnownAccountUuid"] as? String
    }

    /// Cookie `lastActiveOrg` wins; else the only org folder; else the org of the newest usage sample.
    public func orgUuid(cookieOrg: String?) -> String? {
        if let cookieOrg, !cookieOrg.isEmpty { return cookieOrg }
        let orgs = orgFolders()
        if orgs.count == 1 { return orgs[0] }
        guard let latest = usageSamples().max(by: { $0.t < $1.t })?.org else { return nil }
        return orgs.isEmpty || orgs.contains(latest) ? latest : nil
    }

    /// `claude-code-sessions/<account>/<org>`, or nil when not logged in.
    public func sessionsDir(org: String?) -> URL? {
        guard let account = accountUuid, let org else { return nil }
        return url.appendingPathComponent("claude-code-sessions/\(account)/\(org)", isDirectory: true)
    }

    public func sessions() -> [SessionInfo] {
        guard let account = accountUuid else { return [] }
        let fm = FileManager.default
        let root = url.appendingPathComponent("claude-code-sessions/\(account)", isDirectory: true)
        var result: [SessionInfo] = []
        for org in orgFolders() {
            let dir = root.appendingPathComponent(org, isDirectory: true)
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                guard let obj = readJSON(file) as? [String: Any], let id = obj["sessionId"] as? String else {
                    Log.error("Skipping unreadable session file \(file.lastPathComponent)")
                    continue
                }
                result.append(SessionInfo(
                    id: id,
                    title: obj["title"] as? String ?? "",
                    cwd: obj["cwd"] as? String ?? "",
                    lastActivityAt: (obj["lastActivityAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
                    isArchived: obj["isArchived"] as? Bool ?? false,
                    fileURL: file))
            }
        }
        return result.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
    }

    public func snapshotUsage(org: String?) -> UsageSnapshot? {
        guard let org, let s = usageSamples().filter({ $0.org == org }).max(by: { $0.t < $1.t }) else { return nil }
        return UsageSnapshot(fiveHourPct: s.u["fh"], weeklyPct: s.u["sd"], extraPct: s.u["xu"],
                             fetchedAt: Date(timeIntervalSince1970: s.t / 1000), source: .file)
    }

    // MARK: - Private

    private struct Sample { var t: Double; var org: String?; var u: [String: Double] }

    private func usageSamples() -> [Sample] {
        guard let obj = readJSON(url.appendingPathComponent("plan-usage-history.json")) as? [String: Any],
              let samples = obj["samples"] as? [[String: Any]] else { return [] }
        return samples.compactMap { s in
            guard let t = s["t"] as? Double else { return nil }
            let u = (s["u"] as? [String: Any] ?? [:]).compactMapValues { $0 as? Double }
            return Sample(t: t, org: s["org"] as? String, u: u)
        }
    }

    private func orgFolders() -> [String] {
        guard let account = accountUuid else { return [] }
        let root = url.appendingPathComponent("claude-code-sessions/\(account)", isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent).sorted()
    }

    private func readJSON(_ file: URL) -> Any? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

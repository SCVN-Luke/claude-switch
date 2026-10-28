import Foundation

public enum UsageError: Error, Equatable {
    case http(Int), badResponse
}

public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

/// Calls the same endpoint Claude Desktop uses for its usage meter.
public struct UsageClient: Sendable {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Claude/4.29.0 Chrome/138.0.0.0 Electron/37.0.0 Safari/537.36"

    let transport: HTTPTransport

    public init(transport: @escaping HTTPTransport = UsageClient.urlSessionTransport) {
        self.transport = transport
    }

    /// No cookie jar and no cache: claude.ai's Set-Cookie (incl. a rotated sessionKey) must never
    /// reach disk or leak into another profile's request.
    public static var sessionConfiguration: URLSessionConfiguration {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        return cfg
    }

    static let session = URLSession(configuration: sessionConfiguration)

    public static let urlSessionTransport: HTTPTransport = { req in
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UsageError.badResponse }
        return (data, http)
    }

    public func fetch(org: String, sessionKey: String) async throws -> UsageSnapshot {
        var req = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(org)/usage")!)
        req.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        req.httpShouldHandleCookies = false
        let (data, resp) = try await transport(req)
        guard resp.statusCode == 200 else { throw UsageError.http(resp.statusCode) }
        return try Self.parse(data, now: Date())
    }

    public static func parse(_ data: Data, now: Date) throws -> UsageSnapshot {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let five = obj["five_hour"] as? [String: Any] else { throw UsageError.badResponse }
        let week = obj["seven_day"] as? [String: Any]
        let extra = obj["extra_usage"] as? [String: Any]
        return UsageSnapshot(
            fiveHourPct: five["utilization"] as? Double,
            fiveHourResetsAt: date(five["resets_at"]),
            weeklyPct: week?["utilization"] as? Double,
            weeklyResetsAt: date(week?["resets_at"]),
            extraPct: extra?["utilization"] as? Double,
            fetchedAt: now,
            source: .live)
    }

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

public enum ProfileUsageState: Equatable, Sendable {
    case notLoggedIn, usage(UsageSnapshot), unavailable
}

/// Live usage per data dir with a 60 s cache; falls back to Claude's own history file.
public actor UsageService {
    static let cacheTTL: TimeInterval = 60

    let client: UsageClient
    let cookies: CookieSource
    let now: @Sendable () -> Date
    private var cache: [String: (state: ProfileUsageState, at: Date)] = [:]
    public private(set) var keychainDenied = false

    public init(client: UsageClient, cookies: CookieSource, now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.cookies = cookies
        self.now = now
    }

    public func usage(for dataDir: URL, force: Bool) async -> ProfileUsageState {
        let key = dataDir.standardizedFileURL.path
        if !force, let hit = cache[key], now().timeIntervalSince(hit.at) < Self.cacheTTL { return hit.state }
        let state = await load(dataDir)
        cache[key] = (state, now())
        return state
    }

    private func load(_ dataDir: URL) async -> ProfileUsageState {
        let dir = ClaudeDataDir(url: dataDir)
        var cookie: ClaudeCookies?
        var cookieMissing = false
        if !keychainDenied {
            do {
                cookie = try cookies.read(dataDir: dataDir)
            } catch CookieError.keychain(let status) {
                Log.error("Keychain access denied (\(status)); live usage disabled until restart")
                keychainDenied = true
            } catch CookieError.notFound {
                cookieMissing = true
            } catch {
                Log.error("Cookie read failed for \(dataDir.lastPathComponent): \(error)")
            }
        }
        let org = dir.orgUuid(cookieOrg: cookie?.lastActiveOrg)
        if let cookie, let org {
            do {
                var live = try await client.fetch(org: org, sessionKey: cookie.sessionKey)
                live.fetchedAt = now()
                return .usage(live)
            } catch {
                Log.error("Usage API failed for \(dataDir.lastPathComponent): \(error)")
            }
        }
        if let snap = dir.snapshotUsage(org: org) { return .usage(snap) }
        if cookieMissing && dir.accountUuid == nil { return .notLoggedIn }
        return .unavailable
    }
}

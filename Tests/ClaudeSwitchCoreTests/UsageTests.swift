import Foundation
import Testing
@testable import ClaudeSwitchCore

let realShape = """
{"five_hour":{"utilization":50,"resets_at":"2026-10-28T06:20:00.367407+00:00"},
 "seven_day":{"utilization":39,"resets_at":"2026-11-02T07:00:00+00:00"},
 "extra_usage":{"is_enabled":false,"monthly_limit":4000,"used_credits":1051,"utilization":26.275},
 "amber_cistern":{"x":1},"limits":[]}
"""

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    func add(_ r: URLRequest) { lock.lock(); requests.append(r); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
}

func stubClient(status: Int = 200, body: String = realShape, recorder: Recorder = Recorder()) -> UsageClient {
    UsageClient { req in
        recorder.add(req)
        let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), resp)
    }
}

struct FakeCookies: CookieSource {
    var result: Result<ClaudeCookies, CookieError> = .success(ClaudeCookies(sessionKey: "k", lastActiveOrg: "o1"))
    func read(dataDir: URL) throws -> ClaudeCookies { try result.get() }
}

final class Clock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_000_000)
}

struct UsageTests {
    @Test func parseRealShape() throws {
        let now = Date()
        let u = try UsageClient.parse(Data(realShape.utf8), now: now)
        #expect(u.fiveHourPct == 50)
        #expect(u.weeklyPct == 39)
        #expect(u.extraPct == 26.275)
        #expect(u.source == .live)
        #expect(u.fetchedAt == now)
        let expected = ISO8601DateFormatter().date(from: "2026-10-28T06:20:00Z")!
        #expect(abs(u.fiveHourResetsAt!.timeIntervalSince(expected) - 0.367407) < 0.001)
        #expect(u.weeklyResetsAt == ISO8601DateFormatter().date(from: "2026-11-02T07:00:00Z"))
    }

    @Test func parseMissingFiveHourThrows() {
        #expect(throws: UsageError.badResponse) {
            try UsageClient.parse(Data(#"{"seven_day":{"utilization":1}}"#.utf8), now: Date())
        }
    }

    @Test func parseNullUtilization() throws {
        let u = try UsageClient.parse(Data(#"{"five_hour":{"utilization":null,"resets_at":null}}"#.utf8), now: Date())
        #expect(u.fiveHourPct == nil)
        #expect(u.weeklyPct == nil)
    }

    @Test func fetchSendsCookieAndPath() async throws {
        let rec = Recorder()
        _ = try await stubClient(recorder: rec).fetch(org: "o1", sessionKey: "k")
        let req = try #require(rec.requests.first)
        #expect(req.url?.absoluteString == "https://claude.ai/api/organizations/o1/usage")
        #expect(req.value(forHTTPHeaderField: "Cookie") == "sessionKey=k")
        #expect(req.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(req.timeoutInterval == 15)
    }

    @Test func fetch403Throws() async {
        await #expect(throws: UsageError.http(403)) {
            try await stubClient(status: 403, body: "<html>cf</html>").fetch(org: "o1", sessionKey: "k")
        }
        await #expect(throws: UsageError.badResponse) {
            try await stubClient(status: 200, body: "<html>cf</html>").fetch(org: "o1", sessionKey: "k")
        }
    }

    @Test func serviceFallsBackToFile() async {
        let dir = FakeDataDir.make(account: "a", orgs: ["o1"], usageSamples: [["t": 5000, "org": "o1", "u": ["fh": 48]]])
        let svc = UsageService(client: stubClient(status: 403), cookies: FakeCookies())
        let state = await svc.usage(for: dir, force: false)
        guard case .usage(let u) = state else { Issue.record("expected usage, got \(state)"); return }
        #expect(u.source == .file)
        #expect(u.fiveHourPct == 48)
    }

    @Test func serviceLiveWhenApiOk() async {
        let dir = FakeDataDir.make(account: "a", orgs: ["o1"])
        let state = await UsageService(client: stubClient(), cookies: FakeCookies()).usage(for: dir, force: false)
        guard case .usage(let u) = state else { Issue.record("expected usage"); return }
        #expect(u.source == .live && u.fiveHourPct == 50)
    }

    @Test func serviceNotLoggedIn() async {
        let rec = Recorder()
        let svc = UsageService(client: stubClient(recorder: rec), cookies: FakeCookies(result: .failure(.notFound)))
        #expect(await svc.usage(for: makeTempDir(), force: false) == .notLoggedIn)
        #expect(rec.count == 0)
    }

    @Test func serviceUnavailableWithoutAnyData() async {
        let dir = FakeDataDir.make(account: "a", orgs: ["o1"])
        let svc = UsageService(client: stubClient(status: 500), cookies: FakeCookies())
        #expect(await svc.usage(for: dir, force: false) == .unavailable)
    }

    @Test func serviceCachesFor60s() async {
        let dir = FakeDataDir.make(account: "a", orgs: ["o1"])
        let rec = Recorder()
        let clock = Clock()
        let svc = UsageService(client: stubClient(recorder: rec), cookies: FakeCookies(), now: { clock.now })
        _ = await svc.usage(for: dir, force: false)
        clock.now += 30
        _ = await svc.usage(for: dir, force: false)
        #expect(rec.count == 1)
        clock.now += 31
        _ = await svc.usage(for: dir, force: false)
        #expect(rec.count == 2)
        _ = await svc.usage(for: dir, force: true)
        #expect(rec.count == 3)
    }

    @Test func keychainDenialStopsApiCalls() async {
        let dir = FakeDataDir.make(account: "a", orgs: ["o1"], usageSamples: [["t": 5000, "org": "o1", "u": ["fh": 7]]])
        let rec = Recorder()
        let svc = UsageService(client: stubClient(recorder: rec),
                               cookies: FakeCookies(result: .failure(.keychain(-128))))
        guard case .usage(let u) = await svc.usage(for: dir, force: true) else { Issue.record("expected file"); return }
        #expect(u.source == .file)
        #expect(await svc.keychainDenied)
        #expect(rec.count == 0)
    }
}

import Foundation
import Testing
@testable import ClaudeSwitchCore

struct UsageFormatTests {
    let tz = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    func at(_ h: Int, _ m: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        return c.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: h, minute: m))!
    }

    @Test func levels() {
        #expect(UsageFormat.level(nil) == .none)
        #expect(UsageFormat.level(69.9) == .normal)
        #expect(UsageFormat.level(70) == .warning)
        #expect(UsageFormat.level(90) == .warning)
        #expect(UsageFormat.level(90.1) == .critical)
    }

    @Test func liveLine() {
        let u = UsageSnapshot(fiveHourPct: 48, fiveHourResetsAt: at(13, 20), weeklyPct: 33.4, fetchedAt: at(11, 0), source: .live)
        #expect(UsageFormat.line(.usage(u), language: .vi, timeZone: tz) == "5h 48% (reset 13:20) · Tuần 33%")
    }

    @Test func fileLineIsMarkedStale() {
        let u = UsageSnapshot(fiveHourPct: 0, weeklyPct: 33, fetchedAt: at(7, 33), source: .file)
        #expect(UsageFormat.line(.usage(u), language: .vi, timeZone: tz) == "5h 0% · Tuần 33%  ⚠︎ cũ · 07:33")
    }

    @Test func missingValuesAndStates() {
        let u = UsageSnapshot(fiveHourPct: nil, weeklyPct: nil, fetchedAt: at(1, 0), source: .live)
        #expect(UsageFormat.line(.usage(u), language: .vi, timeZone: tz) == "5h — · Tuần —")
        #expect(UsageFormat.line(.unavailable, language: .vi, timeZone: tz) == "—")
        #expect(UsageFormat.line(.notLoggedIn, language: .vi, timeZone: tz) == "chưa đăng nhập")
        #expect(UsageFormat.line(nil, language: .vi, timeZone: tz) == "…")
    }

    @Test func englishAndKorean() {
        let u = UsageSnapshot(fiveHourPct: 48, fiveHourResetsAt: at(13, 20), weeklyPct: 33, fetchedAt: at(7, 33), source: .file)
        #expect(UsageFormat.line(.usage(u), language: .en, timeZone: tz) == "5h 48% (reset 13:20) · Week 33%  ⚠︎ stale · 07:33")
        #expect(UsageFormat.line(.usage(u), language: .ko, timeZone: tz) == "5h 48% (초기화 13:20) · 주간 33%  ⚠︎ 오래됨 · 07:33")
        #expect(UsageFormat.line(.notLoggedIn, language: .en, timeZone: tz) == "not signed in")
    }
}

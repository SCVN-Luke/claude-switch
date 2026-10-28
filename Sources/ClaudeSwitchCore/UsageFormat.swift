import Foundation

/// Menu-bar text and colour level for a profile's usage (spec §5).
public enum UsageFormat {
    public enum Level: Sendable { case none, normal, warning, critical }

    public static func level(_ pct: Double?) -> Level {
        guard let pct else { return .none }
        if pct > 90 { return .critical }
        if pct >= 70 { return .warning }
        return .normal
    }

    /// nil state = not fetched yet.
    public static func line(_ state: ProfileUsageState?, language: AppLanguage,
                            timeZone: TimeZone = .current) -> String {
        guard let state else { return "…" }
        switch state {
        case .notLoggedIn: return L10n.t(.notSignedIn, language)
        case .unavailable: return "—"
        case .usage(let u):
            var five = "5h \(pct(u.fiveHourPct))"
            if let reset = u.fiveHourResetsAt { five += " (\(L10n.t(.usageReset, language)) \(time(reset, timeZone)))" }
            var text = "\(five) · \(L10n.t(.usageWeek, language)) \(pct(u.weeklyPct))"
            if u.source == .file { text += "  ⚠︎ \(L10n.t(.usageStale, language)) · \(time(u.fetchedAt, timeZone))" }
            return text
        }
    }

    static func pct(_ v: Double?) -> String {
        v.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    static func time(_ date: Date, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

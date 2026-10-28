import Foundation

public enum SwitchStep: Equatable, Sendable {
    case needsForceQuit
    case done(transfer: [String: TransferOutcome])
    case failed(String)
}

/// Quit Claude → copy sessions (nobody is writing them now) → launch the target profile.
public final class SwitchCoordinator: Sendable {
    static let notLoggedInMessage = "Hãy mở profile này và đăng nhập một lần trước"
    static let quitTimeout: TimeInterval = 10

    let claude: ClaudeControlling
    let store: ProfileStore
    let cookies: CookieSource
    let defaultDir: URL

    public init(claude: ClaudeControlling, store: ProfileStore, cookies: CookieSource, defaultDir: URL) {
        self.claude = claude
        self.store = store
        self.cookies = cookies
        self.defaultDir = defaultDir
    }

    public func switchTo(_ target: Profile, carrying sessions: [SessionInfo], force: Bool) async -> SwitchStep {
        if await claude.quit(timeout: Self.quitTimeout) == .stillRunning {
            guard force else { return .needsForceQuit }
            await claude.forceQuit()
        }

        let targetURL = target.resolvedDataDir(defaultDir: defaultDir)
        var outcomes: [String: TransferOutcome] = [:]
        if !sessions.isEmpty {
            let dir = ClaudeDataDir(url: targetURL)
            let org = dir.orgUuid(cookieOrg: (try? cookies.read(dataDir: targetURL))?.lastActiveOrg)
            do {
                outcomes = try SessionTransfer.transfer(sessions, to: dir, targetOrg: org)
            } catch {
                for s in sessions { outcomes[s.id] = .failed(Self.notLoggedInMessage) }
            }
        }

        do {
            try await claude.launch(dataDir: target.dataDir == nil ? nil : targetURL)
        } catch {
            Log.error("Launch failed: \(error.localizedDescription)")
            return .failed("Không mở được Claude: \(error.localizedDescription)")
        }
        try? store.setActive(target.id)
        return .done(transfer: outcomes)
    }
}

import Foundation

public enum SwitchStep: Equatable, Sendable {
    case needsForceQuit
    case done(transfer: [String: TransferOutcome])
    case busy
    case claudeMissing
    case launchFailed(String)
}

/// Quit Claude → copy sessions (nobody is writing them now) → launch the target profile.
public final class SwitchCoordinator: @unchecked Sendable {
    static let quitTimeout: TimeInterval = 10

    let claude: ClaudeControlling
    let store: ProfileStore
    let cookies: CookieSource
    let defaultDir: URL
    private let lock = NSLock()
    private var busy = false

    public init(claude: ClaudeControlling, store: ProfileStore, cookies: CookieSource, defaultDir: URL) {
        self.claude = claude
        self.store = store
        self.cookies = cookies
        self.defaultDir = defaultDir
    }

    public func switchTo(_ target: Profile, carrying sessions: [SessionInfo], force: Bool) async -> SwitchStep {
        guard claimBusy() else { return .busy }
        defer { releaseBusy() }
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
                for s in sessions { outcomes[s.id] = .targetNotSignedIn }
            }
        }

        do {
            try await claude.launch(dataDir: target.dataDir == nil ? nil : targetURL)
        } catch LaunchError.claudeNotFound {
            return .claudeMissing
        } catch {
            Log.error("Launch failed: \(error.localizedDescription)")
            return .launchFailed(error.localizedDescription)
        }
        try? store.setActive(target.id)
        return .done(transfer: outcomes)
    }

    private func claimBusy() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }

    private func releaseBusy() {
        lock.lock(); busy = false; lock.unlock()
    }
}

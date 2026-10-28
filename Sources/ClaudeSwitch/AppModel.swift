import AppKit
import ClaudeSwitchCore
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case sessions, profiles, config }

    @Published var profiles: [Profile] = []
    @Published var running: Profile?
    @Published var selected: Profile.ID?
    @Published var usage: [Profile.ID: ProfileUsageState] = [:]
    @Published var sessions: [SessionInfo] = []
    @Published var manageTab: Tab = .sessions
    @Published var transferTarget: Profile.ID?
    @Published var isSwitching = false
    @Published var keychainDenied = false
    @Published private(set) var language: AppLanguage = .en
    @Published var configSource: Profile.ID?
    @Published var configTarget: Profile.ID?
    /// Guide illustrations only: stands in for what would be read from disk.
    var previewServers: [Profile.ID: [MCPServerEntry]] = [:]
    var previewPlugins: [Profile.ID: [String]] = [:]
    var previewCodeMCP: [String] = []

    /// Preview models feed the Guide's illustrations: sample data, no disk, network or Claude access.
    let isPreview: Bool
    let defaultDir = Paths.claudeDefaultDataDir
    private let store = ProfileStore()
    private let launcher = ClaudeLauncher()
    private let usageService: UsageService
    private let coordinator: SwitchCoordinator
    private var timer: Timer?
    private var activeProfileId: UUID?
    private var guideWindow: NSWindow?

    init(preview: Bool = false) {
        isPreview = preview
        let cookies = CookieReader(passwords: KeychainPasswordProvider())
        usageService = UsageService(client: UsageClient(), cookies: cookies)
        coordinator = SwitchCoordinator(claude: launcher, store: store, cookies: cookies, defaultDir: defaultDir)
        guard !preview else { return }

        reloadProfiles()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == ClaudeLauncher.bundleId else { return }
                Task { @MainActor in await self?.refreshRunning() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage(force: false) }
        }
        Task {
            await refreshRunning()
            refreshUsage(force: false)
            showGuideOnFirstRun()
        }
    }

    func t(_ key: L10nKey, _ args: [String: String] = [:]) -> String {
        L10n.t(key, language, args)
    }

    func setLanguage(_ lang: AppLanguage) {
        language = lang
        guideWindow?.title = t(.guideTitle)
        guard !isPreview else { return }
        try? store.setLanguage(lang)
    }

    /// The profile whose sessions can be carried over: the running one, else the last switched-to one.
    var sourceProfile: Profile? {
        running ?? activeProfileId.flatMap { id in profiles.first { $0.id == id } } ?? profiles.first
    }

    func onMenuOpen() {
        guard !isPreview else { return }
        Task { await refreshRunning() }
        refreshUsage(force: false)
    }

    func reloadProfiles() {
        do {
            let file = try store.load()
            profiles = file.profiles
            activeProfileId = file.activeProfileId
            language = file.language ?? AppLanguage.preferred()
        } catch {
            Log.error("Loading profiles failed: \(error)")
            alert(t(.loadFailed), error.localizedDescription)
        }
    }

    func refreshRunning() async {
        guard !isPreview else { return }
        running = matchProfile(await launcher.runningDataDir(), in: profiles, defaultDir: defaultDir)
        reloadSessions()
    }

    func reloadSessions() {
        guard !isPreview else { return }
        guard let source = sourceProfile else { sessions = []; return }
        sessions = ClaudeDataDir(url: source.resolvedDataDir(defaultDir: defaultDir)).sessions()
    }

    func refreshUsage(force: Bool) {
        guard !isPreview else { return }
        for profile in profiles {
            let dir = profile.resolvedDataDir(defaultDir: defaultDir)
            Task {
                let state = await usageService.usage(for: dir, force: force)
                usage[profile.id] = state
                keychainDenied = await usageService.keychainDenied
            }
        }
    }

    // MARK: - Settings carry

    func mcpServers(of profile: Profile) -> [MCPServerEntry] {
        isPreview ? previewServers[profile.id] ?? []
            : DesktopConfig.mcpServers(in: profile.resolvedDataDir(defaultDir: defaultDir))
    }

    func plugins(of profile: Profile) -> [String] {
        isPreview ? previewPlugins[profile.id] ?? []
            : DesktopConfig.installedPlugins(in: profile.resolvedDataDir(defaultDir: defaultDir))
    }

    var codeMCPServers: [String] { isPreview ? previewCodeMCP : DesktopConfig.claudeCodeMCPServers() }

    func configCarry(from source: Profile, servers: [String], toolToggles: Bool) -> ConfigCarry {
        ConfigCarry(source: source.resolvedDataDir(defaultDir: defaultDir), mcpServers: servers, toolToggles: toolToggles)
    }

    /// Writes into a profile Claude is not running on; otherwise asks for "Switch & apply".
    func applyConfig(_ carry: ConfigCarry, to target: Profile) {
        guard !isPreview else { return }
        Task {
            await refreshRunning()
            if running?.id == target.id {
                alert(t(.configResultTitle), t(.applyNeedsQuit, ["name": target.name]))
                return
            }
            reportConfig(carry.apply(to: target.resolvedDataDir(defaultDir: defaultDir)))
        }
    }

    private func reportConfig(_ r: ConfigApplyResult) {
        if let failure = r.failure {
            let reason: L10nKey = switch failure {
            case .sourceUnreadable: .errSourceUnreadable
            case .targetUnreadable: .errTargetUnreadable
            case .targetNotSignedIn: .errTargetNotSignedIn
            }
            alert(t(.configResultTitle), t(.configFailed, ["reason": t(reason)]))
            return
        }
        let added = r.servers.filter { $0.value == .copied }.keys.sorted()
        let skipped = r.servers.filter { $0.value == .alreadyExists }.keys.sorted()
        var lines: [String] = []
        if !added.isEmpty { lines.append(t(.resultServersAdded, ["list": added.joined(separator: ", ")])) }
        if !skipped.isEmpty { lines.append(t(.resultSkipped, ["list": skipped.joined(separator: ", ")])) }
        if let n = r.togglesAdded, n > 0 { lines.append(t(.resultToggles, ["count": "\(n)"])) }
        if lines.isEmpty { lines.append(t(.resultNothing)) }
        lines.append(t(.takesEffectHint))
        alert(t(.configResultTitle), lines.joined(separator: "\n"))
    }

    // MARK: - Guide

    func showGuide() {
        guard !isPreview else { return }
        if guideWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: GuideView().environmentObject(self))
            window.center()
            guideWindow = window
        }
        guideWindow?.title = t(.guideTitle)
        guideWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showGuideOnFirstRun() {
        guard let file = try? store.load(), file.guideShown != true, file.profiles.count == 1 else { return }
        try? store.markGuideShown()
        showGuide()
    }

    // MARK: - Profiles

    func addProfile(name: String) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isPreview else { return nil }
        do {
            let p = try store.addProfile(name: trimmed)
            reloadProfiles()
            refreshUsage(force: false)
            if confirm(t(.openNowTitle), t(.openNowText, ["name": p.name]), ok: t(.openNowButton)) {
                requestSwitch(to: p, carrying: [])
            }
            return p
        } catch {
            alert(t(.createFailed), error.localizedDescription)
            return nil
        }
    }

    func rename(_ profile: Profile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isPreview else { return }
        try? store.rename(id: profile.id, to: trimmed)
        reloadProfiles()
    }

    func remove(_ profile: Profile) {
        guard !isPreview else { return }
        let a = NSAlert()
        a.messageText = t(.removeTitle, ["name": profile.name])
        a.informativeText = t(.removeText)
        a.addButton(withTitle: t(.removeListOnly))
        a.addButton(withTitle: t(.removeWithData))
        a.addButton(withTitle: t(.cancel))
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()
        guard r != .alertThirdButtonReturn else { return }
        do {
            try store.remove(id: profile.id, deleteData: r == .alertSecondButtonReturn,
                             isRunning: running?.id == profile.id)
        } catch ProfileError.profileIsRunning {
            alert(t(.cannotDeleteTitle), t(.cannotDeleteText))
        } catch {
            alert(t(.removeFailed), "\(error)")
        }
        reloadProfiles()
    }

    // MARK: - Switch

    func requestSwitch(to target: Profile, carrying: [SessionInfo], config: ConfigCarry? = nil) {
        // Claimed synchronously so a double-click cannot start two switches.
        guard !isSwitching, !isPreview else { return }
        isSwitching = true
        Task {
            defer { isSwitching = false }
            if await launcher.runningDataDir() != nil {
                let ok = confirm(t(.confirmSwitchTitle, ["name": target.name]), t(.confirmSwitchText),
                                 ok: t(.switchButton))
                guard ok else { return }
            }
            var step = await coordinator.switchTo(target, carrying: carrying, config: config, force: false)
            if step == .needsForceQuit {
                guard confirm(t(.forceQuitTitle), t(.forceQuitText), ok: t(.forceQuitButton)) else { return }
                step = await coordinator.switchTo(target, carrying: carrying, config: config, force: true)
            }
            switch step {
            case .claudeMissing:
                if confirm(t(.switchFailed), t(.claudeMissing), ok: t(.openApplications)) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }
            case .launchFailed(let message):
                alert(t(.switchFailed), t(.launchFailed, ["error": message]))
            case .busy:
                alert(t(.switchFailed), t(.busy))
            case .done(let transfer, let configResult):
                report(transfer, carrying: carrying)
                if let configResult { reportConfig(configResult) }
            case .needsForceQuit:
                break
            }
            await refreshRunning()
            refreshUsage(force: true)
        }
    }

    private func report(_ transfer: [String: TransferOutcome], carrying: [SessionInfo]) {
        let titles = Dictionary(uniqueKeysWithValues: carrying.map { ($0.id, $0.title.isEmpty ? t(.untitled) : $0.title) })
        let problems = transfer.compactMap { id, outcome -> String? in
            let title = titles[id] ?? id
            switch outcome {
            case .copied: return nil
            case .alreadyExists: return "• \(title): \(t(.alreadyThere))"
            case .targetNotSignedIn: return "• \(title): \(t(.transferNotSignedIn))"
            case .failed(let why): return "• \(title): \(why)"
            }
        }.sorted()
        guard !problems.isEmpty else { return }
        alert(t(.transferIssuesTitle), problems.joined(separator: "\n"))
    }

    // MARK: - Alerts

    private func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: t(.cancel))
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

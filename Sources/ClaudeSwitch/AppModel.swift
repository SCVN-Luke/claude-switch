import AppKit
import ClaudeSwitchCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable { case sessions, profiles }

    @Published var profiles: [Profile] = []
    @Published var running: Profile?
    @Published var selected: Profile.ID?
    @Published var usage: [Profile.ID: ProfileUsageState] = [:]
    @Published var sessions: [SessionInfo] = []
    @Published var manageTab: Tab = .sessions
    @Published var transferTarget: Profile.ID?
    @Published var isSwitching = false
    @Published var keychainDenied = false

    let defaultDir = Paths.claudeDefaultDataDir
    private let store = ProfileStore()
    private let launcher = ClaudeLauncher()
    private let usageService: UsageService
    private let coordinator: SwitchCoordinator
    private var timer: Timer?

    init() {
        let cookies = CookieReader(passwords: KeychainPasswordProvider())
        usageService = UsageService(client: UsageClient(), cookies: cookies)
        coordinator = SwitchCoordinator(claude: launcher, store: store, cookies: cookies, defaultDir: defaultDir)
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
        Task { await refreshRunning(); refreshUsage(force: false) }
    }

    /// The profile whose sessions can be carried over: the running one, else the last switched-to one.
    var sourceProfile: Profile? {
        running ?? (try? store.load().activeProfileId).flatMap { id in profiles.first { $0.id == id } } ?? profiles.first
    }

    func onMenuOpen() {
        Task { await refreshRunning() }
        refreshUsage(force: false)
    }

    func reloadProfiles() {
        do {
            profiles = try store.load().profiles
        } catch {
            Log.error("Loading profiles failed: \(error)")
            alert("Không đọc được danh sách profile", error.localizedDescription)
        }
    }

    func refreshRunning() async {
        running = matchProfile(await launcher.runningDataDir(), in: profiles, defaultDir: defaultDir)
        reloadSessions()
    }

    func reloadSessions() {
        guard let source = sourceProfile else { sessions = []; return }
        sessions = ClaudeDataDir(url: source.resolvedDataDir(defaultDir: defaultDir)).sessions()
    }

    func refreshUsage(force: Bool) {
        for profile in profiles {
            let dir = profile.resolvedDataDir(defaultDir: defaultDir)
            Task {
                let state = await usageService.usage(for: dir, force: force)
                usage[profile.id] = state
                keychainDenied = await usageService.keychainDenied
            }
        }
    }

    // MARK: - Profiles

    func addProfile(name: String) -> Profile? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let p = try store.addProfile(name: trimmed)
            reloadProfiles()
            refreshUsage(force: false)
            if confirm("Mở để đăng nhập ngay?", "Claude sẽ mở với profile “\(p.name)” để bạn đăng nhập account.",
                       ok: "Mở ngay") {
                requestSwitch(to: p, carrying: [])
            }
            return p
        } catch {
            alert("Không tạo được profile", error.localizedDescription)
            return nil
        }
    }

    func rename(_ profile: Profile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        try? store.rename(id: profile.id, to: trimmed)
        reloadProfiles()
    }

    func remove(_ profile: Profile) {
        let a = NSAlert()
        a.messageText = "Xoá profile “\(profile.name)”?"
        a.informativeText = "Có xoá luôn dữ liệu đăng nhập của profile này không?"
        a.addButton(withTitle: "Chỉ xoá khỏi danh sách")
        a.addButton(withTitle: "Xoá cả dữ liệu")
        a.addButton(withTitle: "Huỷ")
        NSApp.activate(ignoringOtherApps: true)
        let r = a.runModal()
        guard r != .alertThirdButtonReturn else { return }
        do {
            try store.remove(id: profile.id, deleteData: r == .alertSecondButtonReturn,
                             isRunning: running?.id == profile.id)
        } catch ProfileError.profileIsRunning {
            alert("Không xoá được dữ liệu", "Claude đang chạy với profile này. Hãy switch sang profile khác trước.")
        } catch {
            alert("Không xoá được profile", "\(error)")
        }
        reloadProfiles()
    }

    // MARK: - Switch

    func requestSwitch(to target: Profile, carrying: [SessionInfo]) {
        // Claimed synchronously so a double-click cannot start two switches.
        guard !isSwitching else { return }
        isSwitching = true
        Task {
            defer { isSwitching = false }
            if await launcher.runningDataDir() != nil {
                let ok = confirm("Chuyển sang “\(target.name)”?",
                                 "Claude sẽ được tắt, các phiên đang chạy sẽ dừng.", ok: "Switch")
                guard ok else { return }
            }
            var step = await coordinator.switchTo(target, carrying: carrying, force: false)
            if step == .needsForceQuit {
                guard confirm("Claude chưa tắt. Buộc tắt?", "Claude không tự thoát sau 10 giây.", ok: "Buộc tắt")
                else { return }
                step = await coordinator.switchTo(target, carrying: carrying, force: true)
            }
            switch step {
            case .failed(let message) where message == SwitchCoordinator.claudeMissingMessage:
                if confirm("Switch thất bại", message, ok: "Mở Applications") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                }
            case .failed(let message):
                alert("Switch thất bại", message)
            case .done(let transfer):
                report(transfer, carrying: carrying)
            case .needsForceQuit:
                break
            }
            await refreshRunning()
            refreshUsage(force: true)
        }
    }

    private func report(_ transfer: [String: TransferOutcome], carrying: [SessionInfo]) {
        let titles = Dictionary(uniqueKeysWithValues: carrying.map { ($0.id, $0.title) })
        let problems = transfer.compactMap { id, outcome -> String? in
            switch outcome {
            case .copied: return nil
            case .alreadyExists: return "• \(titles[id] ?? id): đã có"
            case .failed(let why): return "• \(titles[id] ?? id): \(why)"
            }
        }.sorted()
        guard !problems.isEmpty else { return }
        alert("Một số phiên chưa được mang qua", problems.joined(separator: "\n"))
    }

    // MARK: - Alerts

    private func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: "Huỷ")
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

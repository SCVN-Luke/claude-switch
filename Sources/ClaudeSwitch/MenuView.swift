import ClaudeSwitchCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude Switch").font(.headline)
                Spacer()
                Button { model.refreshUsage(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Làm mới usage")
            }
            Divider()
            ForEach(model.profiles) { profile in
                ProfileRow(profile: profile,
                           isRunning: model.running?.id == profile.id,
                           isSelected: model.selected == profile.id,
                           state: model.usage[profile.id])
                    .contentShape(Rectangle())
                    .onTapGesture { model.selected = profile.id }
            }
            Divider()
            HStack {
                Button("Switch") {
                    if let target = selectedProfile { model.requestSwitch(to: target, carrying: []) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSwitch)
                Button("Switch & mang phiên…") {
                    model.transferTarget = model.selected
                    model.manageTab = .sessions
                    model.reloadSessions()
                    openManage()
                }
                .disabled(!canSwitch)
            }
            HStack {
                Button("Quản lý profile…") {
                    model.manageTab = .profiles
                    openManage()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Thoát") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 420)
        .disabled(model.isSwitching)
        .onAppear { model.onMenuOpen() }
    }

    private var selectedProfile: Profile? { model.profiles.first { $0.id == model.selected } }

    private var canSwitch: Bool {
        guard let id = model.selected else { return false }
        return id != model.running?.id
    }

    private func openManage() {
        openWindow(id: "manage")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ProfileRow: View {
    let profile: Profile
    let isRunning: Bool
    let isSelected: Bool
    let state: ProfileUsageState?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").opacity(isRunning ? 1 : 0).frame(width: 14)
            Text(profile.name).fontWeight(isSelected ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 8)
            Text(UsageFormat.line(state))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Color.accentColor.opacity(0.18) : .clear))
    }

    private var color: Color {
        guard case .usage(let u) = state else { return .secondary }
        let worst = [u.fiveHourPct, u.weeklyPct].compactMap { $0 }.max()
        switch UsageFormat.level(worst) {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return u.source == .file ? .secondary : .primary
        case .none: return .secondary
        }
    }
}

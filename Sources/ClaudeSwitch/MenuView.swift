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
                    .help(model.t(.refreshUsage))
            }
            Divider()
            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                ProfileRow(profile: profile,
                           isRunning: model.running?.id == profile.id,
                           isSelected: model.selected == profile.id,
                           state: model.usage[profile.id])
                    .contentShape(Rectangle())
                    .onTapGesture { model.selected = profile.id }
                    .modifier(TagSecondRow(isSecond: index == 1))
            }
            if model.keychainDenied {
                Text(model.t(.keychainHint))
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button(model.t(.switchButton)) {
                    if let target = selectedProfile { model.requestSwitch(to: target, carrying: []) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSwitch)
                .guideTarget(.switchButton)
                Button(model.t(.switchCarry)) {
                    model.transferTarget = model.selected
                    model.manageTab = .sessions
                    model.reloadSessions()
                    openManage()
                }
                .disabled(!canSwitch)
            }
            HStack {
                Button(model.t(.manageProfiles)) {
                    model.manageTab = .profiles
                    openManage()
                }
                .buttonStyle(.borderless)
                .guideTarget(.manageProfiles)
                Button(model.t(.guide)) { model.showGuide() }
                    .buttonStyle(.borderless)
                Spacer()
                LanguagePicker()
                Button(model.t(.quit)) { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(width: 440)
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

private struct TagSecondRow: ViewModifier {
    let isSecond: Bool
    func body(content: Content) -> some View {
        if isSecond { content.guideTarget(.profileRow2) } else { content }
    }
}

struct LanguagePicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker(selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
            ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
        } label: {
            Image(systemName: "globe")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(model.t(.language))
    }
}

struct ProfileRow: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let isRunning: Bool
    let isSelected: Bool
    let state: ProfileUsageState?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").opacity(isRunning ? 1 : 0).frame(width: 14)
            Text(profile.name).fontWeight(isSelected ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 8)
            Text(UsageFormat.line(state, language: model.language))
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

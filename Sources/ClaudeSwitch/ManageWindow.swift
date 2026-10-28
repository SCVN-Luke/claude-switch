import ClaudeSwitchCore
import SwiftUI

struct ManageWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.manageTab) {
            SessionsTab().tabItem { Text(model.t(.tabSessions)) }.tag(AppModel.Tab.sessions)
            ProfilesTab().tabItem { Text(model.t(.tabProfiles)) }.tag(AppModel.Tab.profiles)
            ConfigTab().tabItem { Text(model.t(.tabConfig)) }.tag(AppModel.Tab.config)
        }
        .padding()
        .frame(minWidth: 640, minHeight: 420)
        .disabled(model.isSwitching)
        .environment(\.locale, Locale(identifier: model.language.rawValue))
        .onAppear { model.reloadSessions() }
    }
}

struct SessionsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var checked: Set<String>
    @State private var search = ""
    @State private var showArchived = false

    init(checked: Set<String> = []) {
        _checked = State(initialValue: checked)
    }

    private var visible: [SessionInfo] {
        model.sessions.filter { s in
            (showArchived || !s.isArchived)
                && (search.isEmpty || s.title.localizedCaseInsensitiveContains(search)
                    || s.cwd.localizedCaseInsensitiveContains(search))
        }
    }

    private var targets: [Profile] { model.profiles.filter { $0.id != model.sourceProfile?.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.t(.sessionsOf, ["name": model.sourceProfile?.name ?? "—"])).font(.headline)
            HStack {
                TextField(model.t(.searchPlaceholder), text: $search).textFieldStyle(.roundedBorder)
                Toggle(model.t(.showArchived), isOn: $showArchived)
            }
            List(visible) { s in
                Toggle(isOn: Binding(
                    get: { checked.contains(s.id) },
                    set: { if $0 { checked.insert(s.id) } else { checked.remove(s.id) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title.isEmpty ? model.t(.untitled) : s.title).lineLimit(1)
                        HStack {
                            Text(s.cwd).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if let d = s.lastActivityAt { Text(d, format: .relative(presentation: .named)) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                Picker(model.t(.toProfile), selection: $model.transferTarget) {
                    Text(model.t(.choose)).tag(Profile.ID?.none)
                    ForEach(targets) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                }
                .frame(maxWidth: 280)
                Spacer()
                Text(model.t(.selectedCount, ["count": "\(checked.count)"])).foregroundStyle(.secondary)
                Button(model.t(.switchAndCarry)) {
                    guard let target = targets.first(where: { $0.id == model.transferTarget }) else { return }
                    model.requestSwitch(to: target, carrying: model.sessions.filter { checked.contains($0.id) })
                }
                .disabled(model.transferTarget == nil || !targets.contains { $0.id == model.transferTarget })
                .guideTarget(.switchAndCarry)
            }
        }
    }
}

struct ProfilesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var newName: String

    init(newName: String = "") {
        _newName = State(initialValue: newName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(model.profiles) { profile in
                ProfileEditRow(profile: profile)
            }
            HStack {
                TextField(model.t(.newProfileName), text: $newName).textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(model.t(.add), action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .guideTarget(.addProfile)
            }
            Text(model.t(.loginHint))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func add() {
        guard let p = model.addProfile(name: newName) else { return }
        newName = ""
        model.selected = p.id
    }
}

struct ProfileEditRow: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @State private var name = ""

    var body: some View {
        HStack {
            TextField(model.t(.newProfileName), text: $name)
                .textFieldStyle(.plain)
                .onSubmit { model.rename(profile, to: name) }
            Text(profile.isDefault ? model.t(.defaultProfile) : (profile.dataDir ?? ""))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button(model.t(.openToLogin)) { model.requestSwitch(to: profile, carrying: []) }
                .disabled(model.running?.id == profile.id)
            Button(role: .destructive) { model.remove(profile) } label: { Image(systemName: "trash") }
                .disabled(profile.isDefault || model.running?.id == profile.id)
        }
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { _, new in name = new }
    }
}

/// Carries per-profile Claude Desktop settings (local MCP servers, tool toggles) to another profile,
/// and explains what is already shared or must be redone in the other account.
struct ConfigTab: View {
    @EnvironmentObject var model: AppModel
    @State private var checked: Set<String>
    @State private var toolToggles: Bool

    init(checked: Set<String> = [], toolToggles: Bool = false) {
        _checked = State(initialValue: checked)
        _toolToggles = State(initialValue: toolToggles)
    }

    private var source: Profile? {
        model.profiles.first { $0.id == model.configSource } ?? model.sourceProfile
    }

    private var target: Profile? {
        model.profiles.first { $0.id == model.configTarget && $0.id != source?.id }
            ?? model.profiles.first { $0.id != source?.id }
    }

    private var targetServerNames: Set<String> {
        Set(target.map { model.mcpServers(of: $0).map(\.name) } ?? [])
    }

    private var carry: ConfigCarry? {
        guard let source else { return nil }
        let names = checked.subtracting(targetServerNames).sorted()
        let c = model.configCarry(from: source, servers: names, toolToggles: toolToggles)
        return c.isEmpty ? nil : c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker(model.t(.fromProfile), selection: Binding(
                    get: { source?.id }, set: { model.configSource = $0; checked = [] })) {
                    ForEach(model.profiles) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                }
                Image(systemName: "arrow.right")
                Picker(model.t(.toProfile), selection: Binding(get: { target?.id }, set: { model.configTarget = $0 })) {
                    ForEach(model.profiles.filter { $0.id != source?.id }) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                }
            }

            GroupBox(model.t(.groupCarry)) {
                VStack(alignment: .leading, spacing: 6) {
                    let servers = source.map { model.mcpServers(of: $0) } ?? []
                    if servers.isEmpty {
                        Text(model.t(.noMcpServers)).foregroundStyle(.secondary)
                    }
                    ForEach(servers) { server in
                        let present = targetServerNames.contains(server.name)
                        Toggle(isOn: Binding(
                            get: { present || checked.contains(server.name) },
                            set: { if $0 { checked.insert(server.name) } else { checked.remove(server.name) } })) {
                            HStack {
                                Text(server.name)
                                Text(server.detail).font(.caption).foregroundStyle(.secondary)
                                if present { Text(model.t(.alreadyThere)).font(.caption).foregroundStyle(.green) }
                            }
                        }
                        .disabled(present)
                    }
                    Divider()
                    Toggle(model.t(.toolTogglesRow), isOn: $toolToggles)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox(model.t(.groupShared)) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(model.t(.sharedRules), systemImage: "checkmark.circle.fill")
                    Label(model.t(.sharedSkills), systemImage: "checkmark.circle.fill")
                    Label(model.t(.sharedCodeMcp, ["names": model.codeMCPServers.joined(separator: ", ")]),
                          systemImage: "checkmark.circle.fill")
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox(model.t(.groupRedo)) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(model.t(.connectorsRow)).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(model.t(.openConnectors)) {
                            NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/connectors")!)
                        }
                    }
                    Text(missingPluginsText).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text(model.t(.takesEffectHint)).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(model.t(.applyNow)) {
                    if let carry, let target { model.applyConfig(carry, to: target) }
                }
                .disabled(carry == nil || target == nil)
                Button(model.t(.switchAndApply)) {
                    if let carry, let target { model.requestSwitch(to: target, carrying: [], config: carry) }
                }
                .disabled(carry == nil || target == nil || target?.id == model.running?.id)
                .guideTarget(.applyConfig)
            }
        }
    }

    private var missingPluginsText: String {
        guard let source, let target else { return "" }
        let missing = Set(model.plugins(of: source)).subtracting(model.plugins(of: target)).sorted()
        return missing.isEmpty ? model.t(.pluginsNoneMissing)
            : model.t(.pluginsMissing, ["name": target.name, "list": missing.joined(separator: ", ")])
    }
}

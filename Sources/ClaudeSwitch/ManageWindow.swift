import ClaudeSwitchCore
import SwiftUI

struct ManageWindow: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.manageTab) {
            SessionsTab().tabItem { Text("Mang phiên") }.tag(AppModel.Tab.sessions)
            ProfilesTab().tabItem { Text("Profile") }.tag(AppModel.Tab.profiles)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 420)
        .disabled(model.isSwitching)
        .onAppear { model.reloadSessions() }
    }
}

struct SessionsTab: View {
    @EnvironmentObject var model: AppModel
    @State private var checked: Set<String> = []
    @State private var search = ""
    @State private var showArchived = false

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
            Text("Phiên của “\(model.sourceProfile?.name ?? "—")”").font(.headline)
            HStack {
                TextField("Tìm theo tên hoặc thư mục", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Hiện phiên đã archive", isOn: $showArchived)
            }
            List(visible) { s in
                Toggle(isOn: Binding(
                    get: { checked.contains(s.id) },
                    set: { if $0 { checked.insert(s.id) } else { checked.remove(s.id) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).lineLimit(1)
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
                Picker("Sang profile", selection: $model.transferTarget) {
                    Text("Chọn…").tag(Profile.ID?.none)
                    ForEach(targets) { Text($0.name).tag(Profile.ID?.some($0.id)) }
                }
                .frame(maxWidth: 280)
                Spacer()
                Text("\(checked.count) phiên được chọn").foregroundStyle(.secondary)
                Button("Switch & mang theo") {
                    guard let target = targets.first(where: { $0.id == model.transferTarget }) else { return }
                    model.requestSwitch(to: target, carrying: model.sessions.filter { checked.contains($0.id) })
                }
                .disabled(model.transferTarget == nil || !targets.contains { $0.id == model.transferTarget })
            }
        }
    }
}

struct ProfilesTab: View {
    @EnvironmentObject var model: AppModel
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(model.profiles) { profile in
                ProfileEditRow(profile: profile)
            }
            HStack {
                TextField("Tên profile mới", text: $newName).textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Thêm", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Profile mới cần đăng nhập một lần: bấm “Mở để đăng nhập”, đăng nhập account trong Claude.")
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
            TextField("Tên", text: $name)
                .textFieldStyle(.plain)
                .onSubmit { model.rename(profile, to: name) }
            Text(profile.isDefault ? "Mặc định" : (profile.dataDir ?? ""))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button("Mở để đăng nhập") { model.requestSwitch(to: profile, carrying: []) }
                .disabled(model.running?.id == profile.id)
            Button(role: .destructive) { model.remove(profile) } label: { Image(systemName: "trash") }
                .disabled(profile.isDefault)
        }
        .onAppear { name = profile.name }
        .onChange(of: profile.name) { _, new in name = new }
    }
}

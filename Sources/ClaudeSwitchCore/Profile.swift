import Foundation

public struct Profile: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// nil = Claude Desktop's default data dir (launched without --user-data-dir).
    public var dataDir: String?

    public init(id: UUID = UUID(), name: String, dataDir: String?) {
        self.id = id
        self.name = name
        self.dataDir = dataDir
    }

    public var isDefault: Bool { dataDir == nil }

    public func resolvedDataDir(defaultDir: URL) -> URL {
        dataDir.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultDir
    }
}

public struct ProfilesFile: Codable, Equatable, Sendable {
    public var profiles: [Profile]
    public var activeProfileId: UUID?
}

public enum ProfileError: Error, Equatable {
    case cannotRemoveDefault, notFound
}

/// Persists the profile list in `<root>/profiles.json`; new profile data dirs live in `<root>/Profiles/<id>`.
public final class ProfileStore: @unchecked Sendable {
    public let root: URL
    private var fileURL: URL { root.appendingPathComponent("profiles.json") }

    public init(root: URL = Paths.appSupport) {
        self.root = root
    }

    public func load() throws -> ProfilesFile {
        if let data = try? Data(contentsOf: fileURL) {
            return try JSONDecoder().decode(ProfilesFile.self, from: data)
        }
        let initial = ProfilesFile(profiles: [Profile(name: "Account 1", dataDir: nil)], activeProfileId: nil)
        try save(initial)
        return initial
    }

    public func save(_ file: ProfilesFile) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(file).write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func addProfile(name: String) throws -> Profile {
        var file = try load()
        let id = UUID()
        let dir = root.appendingPathComponent("Profiles/\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profile = Profile(id: id, name: name, dataDir: dir.path)
        file.profiles.append(profile)
        try save(file)
        return profile
    }

    public func rename(id: UUID, to name: String) throws {
        try mutate { file in
            guard let i = file.profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
            file.profiles[i].name = name
        }
    }

    public func remove(id: UUID, deleteData: Bool) throws {
        try mutate { file in
            guard let i = file.profiles.firstIndex(where: { $0.id == id }) else { throw ProfileError.notFound }
            let profile = file.profiles[i]
            guard let dir = profile.dataDir else { throw ProfileError.cannotRemoveDefault }
            file.profiles.remove(at: i)
            if file.activeProfileId == id { file.activeProfileId = nil }
            if deleteData { try? FileManager.default.removeItem(atPath: dir) }
        }
    }

    public func setActive(_ id: UUID?) throws {
        try mutate { $0.activeProfileId = id }
    }

    private func mutate(_ body: (inout ProfilesFile) throws -> Void) throws {
        var file = try load()
        try body(&file)
        try save(file)
    }
}

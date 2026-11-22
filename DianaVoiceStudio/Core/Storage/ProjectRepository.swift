import Foundation

/// File-based persistence of projects (one folder per project:
/// `project.json` + `master.caf`). Plain Foundation so it can be unit-tested anywhere.
struct ProjectRepository: Sendable {
    let root: URL

    static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Projects", isDirectory: true)
    }

    init(root: URL = ProjectRepository.defaultRoot) {
        self.root = root
    }

    func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func audioURL(for project: VoiceProject) -> URL? {
        guard let name = project.audioFileName else { return nil }
        let url = folder(for: project.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func newAudioURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("master-\(Int(Date().timeIntervalSince1970)).caf")
    }

    func loadAll() -> [VoiceProject] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")) else { return nil }
            return try? decoder.decode(VoiceProject.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ project: VoiceProject) throws {
        let folder = folder(for: project.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: folder.appendingPathComponent("project.json"), options: .atomic)
    }

    func delete(_ id: UUID) throws {
        let folder = folder(for: id)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Removes master files that are no longer referenced by the project.
    func cleanAudio(of project: VoiceProject) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: folder(for: project.id), includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "caf" && file.lastPathComponent != project.audioFileName {
            try? fm.removeItem(at: file)
        }
    }

    func totalSize() -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

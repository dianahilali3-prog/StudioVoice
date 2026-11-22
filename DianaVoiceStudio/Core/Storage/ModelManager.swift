import Foundation
import Observation

/// Installs, locates and removes the Supertonic voice pack.
///
/// Lookup order:
/// 1. Models bundled inside the app (`Resources/SupertonicModels.bundle`, optional — see README),
/// 2. Models downloaded/imported into Application Support.
@Observable
@MainActor
final class ModelManager {
    enum State: Equatable {
        case notInstalled
        case downloading
        case installed
        case failed(String)
    }

    private(set) var state: State = .notInstalled
    private(set) var downloadedBytes: Int64 = 0
    private(set) var currentFile: String = ""
    private(set) var isBundled = false

    var fraction: Double {
        Double(downloadedBytes) / Double(max(1, SupertonicModelFiles.totalApproximateBytes))
    }

    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    nonisolated static var installDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models/supertonic-3", isDirectory: true)
    }

    nonisolated static var bundledDirectory: URL? {
        guard let url = Bundle.main.url(forResource: "SupertonicModels", withExtension: "bundle") else { return nil }
        let files = SupertonicModelFiles(root: url)
        return files.isComplete ? url : nil
    }

    /// Thread-safe lookup used by the engine.
    nonisolated static func locate() -> SupertonicModelFiles? {
        if let bundled = bundledDirectory { return SupertonicModelFiles(root: bundled) }
        let files = SupertonicModelFiles(root: installDirectory)
        return files.isComplete ? files : nil
    }

    init() {
        refresh()
    }

    func refresh() {
        guard state != .downloading else { return }
        isBundled = Self.bundledDirectory != nil
        state = Self.locate() != nil ? .installed : .notInstalled
    }

    var installedSize: Int64 {
        guard let files = Self.locate() else { return 0 }
        return SupertonicModelFiles.entries.reduce(0) { total, entry in
            let path = files.root.appendingPathComponent(entry.path).path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            return total + size
        }
    }

    // MARK: - Download

    func download() {
        guard state != .downloading else { return }
        state = .downloading
        downloadedBytes = 0
        downloadTask = Task { [weak self] in
            do {
                try await self?.performDownload()
                await MainActor.run { self?.state = .installed; self?.currentFile = "" }
            } catch is CancellationError {
                await MainActor.run { self?.state = .notInstalled; self?.currentFile = "" }
            } catch {
                await MainActor.run { self?.state = .failed(error.localizedDescription); self?.currentFile = "" }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    private func performDownload() async throws {
        let fm = FileManager.default
        let root = Self.installDirectory
        try fm.createDirectory(at: root.appendingPathComponent("onnx"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("voice_styles"), withIntermediateDirectories: true)
        var rootValues = URLResourceValues()
        rootValues.isExcludedFromBackup = true
        var mutableRoot = root.deletingLastPathComponent()
        try? mutableRoot.setResourceValues(rootValues)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var completedBytes: Int64 = 0
        for entry in SupertonicModelFiles.entries {
            try Task.checkCancellation()
            let destination = root.appendingPathComponent(entry.path)
            if let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value, size > 0 {
                completedBytes += entry.approximateBytes
                downloadedBytes = completedBytes
                continue
            }
            currentFile = (entry.path as NSString).lastPathComponent
            var lastError: Error = URLError(.cannotFindHost)
            var success = false
            for base in SupertonicModelFiles.baseURLs {
                do {
                    let url = base.appendingPathComponent(entry.path)
                    let baseline = completedBytes
                    try await downloadFile(from: url, to: destination, session: session) { [weak self] received in
                        Task { @MainActor in self?.downloadedBytes = baseline + received }
                    }
                    success = true
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                }
            }
            guard success else { throw lastError }
            completedBytes += entry.approximateBytes
            downloadedBytes = completedBytes
        }
        guard SupertonicModelFiles(root: root).isComplete else {
            throw SupertonicError.invalidModel("téléchargement incomplet")
        }
    }

    private nonisolated func downloadFile(from url: URL, to destination: URL, session: URLSession,
                                          onBytes: @escaping @Sendable (Int64) -> Void) async throws {
        let delegate = DownloadProgressDelegate(onBytes: onBytes)
        let (temporary, response) = try await session.download(from: url, delegate: delegate)
        delegate.stop()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw URLError(.badServerResponse)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: temporary, to: destination)
    }

    // MARK: - Import / delete

    /// Imports a folder previously copied to the device (Files app, AirDrop…)
    /// containing `onnx/` and `voice_styles/` — useful without Wi-Fi.
    func importFolder(_ folder: URL) throws {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let source = SupertonicModelFiles(root: folder)
        guard source.isComplete else {
            throw SupertonicError.invalidModel("le dossier doit contenir « onnx » et « voice_styles » de Supertonic 3")
        }
        let fm = FileManager.default
        let root = Self.installDirectory
        for entry in SupertonicModelFiles.entries {
            let from = folder.appendingPathComponent(entry.path)
            let to = root.appendingPathComponent(entry.path)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: from, to: to)
        }
        refresh()
    }

    func delete() {
        cancelDownload()
        try? FileManager.default.removeItem(at: Self.installDirectory)
        state = .notInstalled
        downloadedBytes = 0
        refresh()
    }
}

/// Reports download progress of the async `URLSession.download` API.
private final class DownloadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onBytes: @Sendable (Int64) -> Void
    private var observation: NSKeyValueObservation?

    init(onBytes: @escaping @Sendable (Int64) -> Void) {
        self.onBytes = onBytes
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let onBytes = self.onBytes
        observation = task.progress.observe(\.completedUnitCount, options: [.new]) { progress, _ in
            onBytes(progress.completedUnitCount)
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }
}

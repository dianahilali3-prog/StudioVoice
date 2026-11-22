import AVFoundation
import Foundation
import Observation
import UIKit

enum AppTab: Hashable {
    case studio, library, voices, settings
}

enum GenerationState: Equatable {
    case idle
    case running(GenerationProgress)
    case failed(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Central state of the app: current project, library, engines, generation and export.
@Observable
@MainActor
final class AppModel {
    let settings = AppSettings()
    let models = ModelManager()
    let player = AudioPlayerController()

    var selectedTab: AppTab = .studio
    private(set) var projects: [VoiceProject] = []
    var project: VoiceProject {
        didSet { if project != oldValue { scheduleAutosave() } }
    }
    private(set) var generationState: GenerationState = .idle
    private(set) var appleVoices: [Voice] = []
    private(set) var previewingVoiceID: String?
    private(set) var loadingPreviewVoiceID: String?
    /// Incremented after each successful generation (drives haptics/animations).
    private(set) var completedGenerations = 0
    var alertMessage: String?
    var showModelRequiredAlert = false

    @ObservationIgnored let repository = ProjectRepository()
    @ObservationIgnored private let supertonic = SupertonicEngine(locateModel: { ModelManager.locate() },
                                                                 useNeuralEngine: { AppSettings.neuralEngineFlag.get() })
    @ObservationIgnored private let apple = AppleSpeechEngine()
    @ObservationIgnored private var generationTask: Task<Void, Never>?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private let previewPlayer = PreviewPlayer()
    @ObservationIgnored private var memoryObserver: NSObjectProtocol?

    init() {
        project = VoiceProject()
        projects = repository.loadAll()
        if let id = settings.lastProjectID, let last = projects.first(where: { $0.id == id }) {
            project = last
        } else {
            project = Self.makeProject(defaults: settings.defaultSynthesis)
        }
        appleVoices = AppleSpeechEngine.availableVoices()
        player.load(repository.audioURL(for: project))
        previewPlayer.onFinish = { [weak self] in self?.previewingVoiceID = nil }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.generationState.isRunning else { return }
                self.supertonic.unload()
            }
        }
    }

    private static func makeProject(defaults: SynthesisSettings) -> VoiceProject {
        var project = VoiceProject()
        project.settings = defaults
        return project
    }

    // MARK: - Voices

    var allVoices: [Voice] { VoiceCatalog.supertonicVoices + appleVoices }

    var selectedVoice: Voice {
        voice(withID: project.voiceID)
    }

    func voice(withID id: String) -> Voice {
        allVoices.first { $0.id == id }
            ?? VoiceCatalog.supertonicVoice(id: VoiceCatalog.defaultVoiceID)!
    }

    func refreshSystemVoices() {
        appleVoices = AppleSpeechEngine.availableVoices()
    }

    func isAvailable(_ voice: Voice) -> Bool {
        voice.engine == .appleSystem || models.state == .installed
    }

    private func engine(for voice: Voice) -> SpeechEngine {
        voice.engine == .supertonic ? supertonic : apple
    }

    // MARK: - Projects

    func newProject() {
        saveNow()
        player.stop()
        var fresh = Self.makeProject(defaults: settings.defaultSynthesis)
        fresh.voiceID = project.voiceID
        project = fresh
        settings.lastProjectID = fresh.id
        player.load(nil)
        selectedTab = .studio
    }

    func open(_ selected: VoiceProject) {
        guard selected.id != project.id else { selectedTab = .studio; return }
        saveNow()
        player.stop()
        project = selected
        settings.lastProjectID = selected.id
        player.load(repository.audioURL(for: selected))
        selectedTab = .studio
    }

    func duplicate(_ source: VoiceProject) {
        var copy = source
        copy.id = UUID()
        copy.title = source.displayTitle + " (copie)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.audioFileName = nil
        copy.audioDuration = nil
        copy.audioFingerprint = nil
        try? repository.save(copy)
        projects = repository.loadAll()
    }

    func delete(_ ids: Set<UUID>) {
        for id in ids { try? repository.delete(id) }
        projects.removeAll { ids.contains($0.id) }
        if ids.contains(project.id) {
            player.load(nil)
            project = Self.makeProject(defaults: settings.defaultSynthesis)
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Saves the current project (only once it contains something).
    func saveNow() {
        autosaveTask?.cancel()
        let hasContent = !project.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !project.title.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasContent else { return }
        var toSave = project
        if let existing = projects.first(where: { $0.id == toSave.id }), existing == toSave { return }
        toSave.updatedAt = Date()
        do {
            try repository.save(toSave)
            settings.lastProjectID = toSave.id
            if let index = projects.firstIndex(where: { $0.id == toSave.id }) {
                projects[index] = toSave
            } else {
                projects.insert(toSave, at: 0)
            }
            projects.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            alertMessage = "Sauvegarde impossible : \(error.localizedDescription)"
        }
    }

    // MARK: - Generation

    func generate() {
        guard !generationState.isRunning else { return }
        let voice = selectedVoice
        guard isAvailable(voice) else {
            showModelRequiredAlert = true
            return
        }
        guard TextSegmenter.containsSpeakableContent(project.script) else {
            alertMessage = "Écrivez ou collez d'abord votre script."
            return
        }
        player.stop()
        stopPreview()
        saveNowForced()

        let projectID = project.id
        let output = repository.newAudioURL(for: projectID)
        let segmenter = TextSegmenter(maxLength: voice.language == .arabic ? 260 : 300)
        let pipeline = SynthesisPipeline(engine: engine(for: voice), segmenter: segmenter)
        let script = project.script
        let settingsSnapshot = project.settings
        let seed = project.seed
        let fingerprint = project.currentFingerprint

        generationState = .running(GenerationProgress())
        UIApplication.shared.isIdleTimerDisabled = true
        let background = UIApplication.shared.beginBackgroundTask(withName: "generation")

        let reportProgress: @Sendable (GenerationProgress) -> Void = { progress in
            Task { @MainActor [weak self] in
                guard let self, self.generationState.isRunning else { return }
                self.generationState = .running(progress)
            }
        }

        generationTask = Task { [weak self] in
            defer {
                UIApplication.shared.isIdleTimerDisabled = false
                if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
            }
            do {
                let result = try await pipeline.run(text: script, voice: voice, settings: settingsSnapshot,
                                                    seed: seed, output: output, onProgress: reportProgress)
                guard let self else { return }
                if self.project.id == projectID {
                    self.project.audioFileName = result.url.lastPathComponent
                    self.project.audioDuration = result.duration
                    self.project.audioFingerprint = fingerprint
                    self.saveNowForced()
                    self.repository.cleanAudio(of: self.project)
                    self.player.load(result.url)
                } else if var other = self.projects.first(where: { $0.id == projectID }) {
                    other.audioFileName = result.url.lastPathComponent
                    other.audioDuration = result.duration
                    other.audioFingerprint = fingerprint
                    try? self.repository.save(other)
                    self.repository.cleanAudio(of: other)
                    self.projects = self.repository.loadAll()
                }
                self.generationState = .idle
                self.completedGenerations += 1
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: output)
                self?.generationState = .idle
            } catch {
                try? FileManager.default.removeItem(at: output)
                if Task.isCancelled {
                    self?.generationState = .idle
                } else {
                    self?.generationState = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        generationState = .idle
    }

    func dismissGenerationError() {
        if case .failed = generationState { generationState = .idle }
    }

    private func saveNowForced() {
        var toSave = project
        toSave.updatedAt = Date()
        try? repository.save(toSave)
        settings.lastProjectID = toSave.id
        if let index = projects.firstIndex(where: { $0.id == toSave.id }) {
            projects[index] = toSave
        } else {
            projects.insert(toSave, at: 0)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Export

    var currentAudioURL: URL? { repository.audioURL(for: project) }

    static var exportsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    /// Converts the master audio to the requested format inside
    /// `Documents/Exports` (visible in the Files app) and returns its URL.
    func export(_ format: ExportFormat, project target: VoiceProject? = nil) async throws -> URL {
        let target = target ?? project
        guard let master = repository.audioURL(for: target) else { throw AudioError.emptyAudio }
        let directory = Self.exportsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(target.exportBaseName).appendingPathExtension(format.fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(target.exportBaseName) (\(counter))").appendingPathExtension(format.fileExtension)
            counter += 1
        }
        let outputSettings = AudioRenderer.settings(for: format, wavBitDepth: settings.wavBitDepth, aacBitRate: settings.aacBitRate)
        let destination = url
        try await Task.detached(priority: .userInitiated) {
            try AudioRenderer.convert(input: master, output: destination, outputSettings: outputSettings)
        }.value
        return url
    }

    // MARK: - Voice preview

    func togglePreview(_ voice: Voice) {
        if previewingVoiceID == voice.id || loadingPreviewVoiceID == voice.id {
            stopPreview()
            return
        }
        stopPreview()
        guard isAvailable(voice) else {
            showModelRequiredAlert = true
            return
        }
        player.pause()
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Previews", isDirectory: true)
        let url = cache.appendingPathComponent("\(voice.id).caf")
        if FileManager.default.fileExists(atPath: url.path) {
            playPreview(url, voiceID: voice.id)
            return
        }
        loadingPreviewVoiceID = voice.id
        let engine = engine(for: voice)
        previewTask = Task { [weak self] in
            do {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                let request = EngineRequest(text: VoiceCatalog.previewText(for: voice), language: voice.language, voice: voice,
                                            speed: 1.0, steps: SynthesisQuality.balanced.rawValue, seed: 2024,
                                            isCancelled: { Task.isCancelled })
                let samples = try await engine.synthesize(request)
                try Task.checkCancellation()
                let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
                let gain = SynthesisSettings.normalizationGain(forPeak: peak)
                let sink = try AudioFileSink(url: url, sampleRate: engine.sampleRate)
                try sink.write(samples.map { $0 * gain }[...])
                guard let self, self.loadingPreviewVoiceID == voice.id else { return }
                self.loadingPreviewVoiceID = nil
                self.playPreview(url, voiceID: voice.id)
            } catch {
                try? FileManager.default.removeItem(at: url)
                guard let self, self.loadingPreviewVoiceID == voice.id else { return }
                self.loadingPreviewVoiceID = nil
                if !(error is CancellationError) { self.alertMessage = error.localizedDescription }
            }
        }
    }

    private func playPreview(_ url: URL, voiceID: String) {
        if previewPlayer.play(url) { previewingVoiceID = voiceID }
    }

    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
        loadingPreviewVoiceID = nil
        previewingVoiceID = nil
        previewPlayer.stop()
    }

    func clearPreviewCache() {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Previews", isDirectory: true)
        try? FileManager.default.removeItem(at: cache)
    }
}

/// Small player for voice samples.
@MainActor
final class PreviewPlayer: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    private var player: AVAudioPlayer?

    func play(_ url: URL) -> Bool {
        stop()
        AudioSessionManager.activatePlayback()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.delegate = self
        self.player = player
        return player.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.onFinish?()
        }
    }
}

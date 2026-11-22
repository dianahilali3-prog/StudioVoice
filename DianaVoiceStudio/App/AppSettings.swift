import Foundation
import Observation

/// Global preferences (persisted in UserDefaults).
@Observable
@MainActor
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var exportFormat: ExportFormat { didSet { defaults.set(exportFormat.rawValue, forKey: Keys.exportFormat) } }
    var wavBitDepth: Int { didSet { defaults.set(wavBitDepth, forKey: Keys.wavBitDepth) } }
    var aacBitRate: Int { didSet { defaults.set(aacBitRate, forKey: Keys.aacBitRate) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    var useNeuralEngine: Bool {
        didSet {
            defaults.set(useNeuralEngine, forKey: Keys.neuralEngine)
            Self.neuralEngineFlag.set(useNeuralEngine)
        }
    }
    /// Default settings applied to new projects.
    var defaultSynthesis: SynthesisSettings {
        didSet {
            if let data = try? JSONEncoder().encode(defaultSynthesis) { defaults.set(data, forKey: Keys.defaultSynthesis) }
        }
    }
    var lastProjectID: UUID? {
        didSet { defaults.set(lastProjectID?.uuidString, forKey: Keys.lastProject) }
    }

    /// Thread-safe mirror read by the engine on its own queue.
    nonisolated static let neuralEngineFlag = AtomicFlag()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        exportFormat = ExportFormat(rawValue: defaults.string(forKey: Keys.exportFormat) ?? "") ?? .wav
        let depth = defaults.integer(forKey: Keys.wavBitDepth)
        wavBitDepth = [16, 24, 32].contains(depth) ? depth : 16
        let rate = defaults.integer(forKey: Keys.aacBitRate)
        aacBitRate = rate > 0 ? rate : 192_000
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        useNeuralEngine = defaults.bool(forKey: Keys.neuralEngine)
        if let data = defaults.data(forKey: Keys.defaultSynthesis),
           let value = try? JSONDecoder().decode(SynthesisSettings.self, from: data) {
            defaultSynthesis = value
        } else {
            defaultSynthesis = SynthesisSettings()
        }
        lastProjectID = defaults.string(forKey: Keys.lastProject).flatMap(UUID.init(uuidString:))
        Self.neuralEngineFlag.set(useNeuralEngine)
    }

    private enum Keys {
        static let exportFormat = "exportFormat"
        static let wavBitDepth = "wavBitDepth"
        static let aacBitRate = "aacBitRate"
        static let haptics = "haptics"
        static let neuralEngine = "useNeuralEngine"
        static let defaultSynthesis = "defaultSynthesis"
        static let lastProject = "lastProjectID"
    }
}

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock(); value = newValue; lock.unlock()
    }

    func get() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

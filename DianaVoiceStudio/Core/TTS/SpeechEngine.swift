import Foundation

/// What a synthesis engine receives for one segment.
struct EngineRequest: Sendable {
    var text: String
    var language: VoiceLanguage
    var voice: Voice
    /// Speed applied natively by the engine (already clamped to `nativeSpeedRange`).
    var speed: Double
    /// Flow-matching steps (quality).
    var steps: Int
    var seed: UInt64
    var isCancelled: @Sendable () -> Bool
}

/// Common interface of all on-device engines.
protocol SpeechEngine: AnyObject, Sendable {
    /// Sample rate of the returned audio (mono Float32).
    var sampleRate: Double { get }
    /// Speed range the engine can produce natively; the remainder is applied by time-stretching.
    var nativeSpeedRange: ClosedRange<Double> { get }
    /// Loads models if necessary (lazy loading). Safe to call several times.
    func prepare() async throws
    func synthesize(_ request: EngineRequest) async throws -> [Float]
    /// Releases large resources (called on memory warnings).
    func unload()
}

/// Supertonic 3 engine. ONNX inference is blocking, so it runs on a private
/// serial queue instead of the Swift cooperative thread pool.
final class SupertonicEngine: SpeechEngine, @unchecked Sendable {
    let sampleRate: Double = 44_100
    let nativeSpeedRange: ClosedRange<Double> = 0.7...2.0

    private let queue = DispatchQueue(label: "studio.diana.voice.supertonic", qos: .userInitiated)
    private let locateModel: @Sendable () -> SupertonicModelFiles?
    private let useNeuralEngine: @Sendable () -> Bool

    // Accessed only on `queue`.
    private var runtime: SupertonicRuntime?
    private var processor: SupertonicTextProcessor?
    private var styles: [String: VoiceStyle] = [:]
    private var loadedRoot: URL?
    private var loadedWithNeuralEngine = false

    init(locateModel: @escaping @Sendable () -> SupertonicModelFiles?,
         useNeuralEngine: @escaping @Sendable () -> Bool = { false }) {
        self.locateModel = locateModel
        self.useNeuralEngine = useNeuralEngine
    }

    func prepare() async throws {
        try await perform { try self.loadIfNeeded() }
    }

    func synthesize(_ request: EngineRequest) async throws -> [Float] {
        try await perform {
            try self.loadIfNeeded()
            guard let runtime = self.runtime, let processor = self.processor else { throw SupertonicError.modelNotInstalled }
            guard let ids = processor.encode(request.text, language: request.language.rawValue) else { return [] }
            let style = try self.style(named: request.voice.engineVoiceID)
            var random = SeededRandom(seed: request.seed)
            return try runtime.synthesize(tokenIDs: ids,
                                          style: style,
                                          steps: request.steps,
                                          speed: Float(request.speed),
                                          random: &random,
                                          isCancelled: request.isCancelled)
        }
    }

    func unload() {
        queue.async {
            self.runtime = nil
            self.styles = [:]
            self.loadedRoot = nil
        }
    }

    // MARK: - Private (queue only)

    private func perform<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func loadIfNeeded() throws {
        guard let files = locateModel(), files.isComplete else {
            runtime = nil
            throw SupertonicError.modelNotInstalled
        }
        let neural = useNeuralEngine()
        if runtime != nil, loadedRoot == files.root, loadedWithNeuralEngine == neural { return }
        runtime = nil
        styles = [:]
        processor = try SupertonicTextProcessor(indexerURL: files.unicodeIndexer)
        runtime = try SupertonicRuntime(files: files, useNeuralEngine: neural)
        loadedRoot = files.root
        loadedWithNeuralEngine = neural
    }

    private func style(named name: String) throws -> VoiceStyle {
        if let cached = styles[name] { return cached }
        guard let files = locateModel() else { throw SupertonicError.modelNotInstalled }
        let style = try VoiceStyle.load(from: files.style(name))
        styles[name] = style
        return style
    }
}

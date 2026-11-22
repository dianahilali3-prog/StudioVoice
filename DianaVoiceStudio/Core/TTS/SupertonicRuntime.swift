import Foundation

#if os(iOS)
import OnnxRuntimeBindings

/// Thin wrapper around the four Supertonic ONNX graphs:
/// duration predictor → text encoder → flow-matching vector estimator (N steps) → vocoder.
///
/// Not thread-safe: always used from `SupertonicEngine`'s private serial queue.
final class SupertonicRuntime {
    let config: SupertonicConfig
    private let env: ORTEnv
    private let durationPredictor: ORTSession
    private let textEncoder: ORTSession
    private let vectorEstimator: ORTSession
    private let vocoder: ORTSession

    init(files: SupertonicModelFiles, useNeuralEngine: Bool) throws {
        config = (try? SupertonicConfig.load(from: files.config)) ?? .fallback
        env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let threads = Int32(max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6)))

        func makeSession(_ url: URL, allowCoreML: Bool) throws -> ORTSession {
            let options = try ORTSessionOptions()
            try options.setGraphOptimizationLevel(ORTGraphOptimizationLevel.all)
            try options.setIntraOpNumThreads(threads)
            if allowCoreML && useNeuralEngine && ORTIsCoreMLExecutionProviderAvailable() {
                let coreML = ORTCoreMLExecutionProviderOptions()
                coreML.enableOnSubgraphs = true
                try? options.appendCoreMLExecutionProvider(with: coreML)
            }
            return try ORTSession(env: env, modelPath: url.path, sessionOptions: options)
        }

        durationPredictor = try makeSession(files.durationPredictor, allowCoreML: false)
        textEncoder = try makeSession(files.textEncoder, allowCoreML: true)
        vectorEstimator = try makeSession(files.vectorEstimator, allowCoreML: true)
        vocoder = try makeSession(files.vocoder, allowCoreML: true)
    }

    /// Synthesizes one segment and returns mono Float32 samples at `config.sampleRate`.
    func synthesize(tokenIDs: [Int64],
                    style: VoiceStyle,
                    steps: Int,
                    speed: Float,
                    random: inout SeededRandom,
                    isCancelled: () -> Bool) throws -> [Float] {
        let length = tokenIDs.count
        guard length > 0 else { return [] }

        let ids = try Self.tensor(tokenIDs, shape: [1, length])
        let textMask = try Self.tensor([Float](repeating: 1, count: length), shape: [1, 1, length])
        let styleTTL = try Self.tensor(style.ttl, shape: style.ttlShape)
        let styleDP = try Self.tensor(style.dp, shape: style.dpShape)

        // 1. Duration (seconds).
        let durationOut = try durationPredictor.run(withInputs: ["text_ids": ids, "style_dp": styleDP, "text_mask": textMask],
                                                    outputNames: ["duration"], runOptions: nil)
        guard let durationValue = durationOut["duration"], let rawDuration = try Self.floats(durationValue).first,
              rawDuration.isFinite, rawDuration > 0 else {
            throw SupertonicError.inference("durée invalide")
        }
        // Guard against degenerate predictions on odd inputs (max 2 minutes per segment).
        let duration = min(Double(rawDuration / max(speed, 0.1)), 120)

        // 2. Text embedding.
        let embeddingOut = try textEncoder.run(withInputs: ["text_ids": ids, "style_ttl": styleTTL, "text_mask": textMask],
                                               outputNames: ["text_emb"], runOptions: nil)
        guard let textEmbedding = embeddingOut["text_emb"] else { throw SupertonicError.inference("text_emb manquant") }

        // 3. Flow matching from Gaussian noise.
        let wavLength = Int(duration * Double(config.sampleRate))
        let latentLength = config.latentLength(forSamples: wavLength)
        let channels = config.latentChannels
        var latent = try Self.tensor(random.gaussian(count: channels * latentLength), shape: [1, channels, latentLength])
        let latentMask = try Self.tensor([Float](repeating: 1, count: latentLength), shape: [1, 1, latentLength])
        let totalStep = try Self.tensor([Float(steps)], shape: [1])

        for step in 0..<steps {
            if isCancelled() { throw CancellationError() }
            let currentStep = try Self.tensor([Float(step)], shape: [1])
            let out = try vectorEstimator.run(withInputs: [
                "noisy_latent": latent,
                "text_emb": textEmbedding,
                "style_ttl": styleTTL,
                "latent_mask": latentMask,
                "text_mask": textMask,
                "current_step": currentStep,
                "total_step": totalStep
            ], outputNames: ["denoised_latent"], runOptions: nil)
            guard let next = out["denoised_latent"] else { throw SupertonicError.inference("latent manquant") }
            latent = next
        }

        // 4. Vocoder.
        let wavOut = try vocoder.run(withInputs: ["latent": latent], outputNames: ["wav_tts"], runOptions: nil)
        guard let wavValue = wavOut["wav_tts"] else { throw SupertonicError.inference("audio manquant") }
        var wav = try Self.floats(wavValue)
        if wav.count > wavLength { wav.removeLast(wav.count - wavLength) }
        return wav
    }

    // MARK: - Tensor helpers

    private static func tensor<T>(_ values: [T], shape: [Int]) throws -> ORTValue {
        let elementType: ORTTensorElementDataType
        switch T.self {
        case is Float.Type: elementType = .float
        case is Int64.Type: elementType = .int64
        default: throw SupertonicError.inference("type de tenseur non géré")
        }
        let data = values.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress, length: $0.count) }
        return try ORTValue(tensorData: data, elementType: elementType, shape: shape.map { NSNumber(value: $0) })
    }

    private static func floats(_ value: ORTValue) throws -> [Float] {
        let data = try value.tensorData() as Data
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

#else

/// Stub used off iOS (e.g. Linux unit-test builds of the pure logic).
final class SupertonicRuntime {
    let config = SupertonicConfig.fallback

    init(files: SupertonicModelFiles, useNeuralEngine: Bool) throws {
        throw SupertonicError.runtimeUnavailable
    }

    func synthesize(tokenIDs: [Int64], style: VoiceStyle, steps: Int, speed: Float,
                    random: inout SeededRandom, isCancelled: () -> Bool) throws -> [Float] {
        throw SupertonicError.runtimeUnavailable
    }
}

#endif

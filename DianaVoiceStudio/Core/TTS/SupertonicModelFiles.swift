import Foundation

/// Layout of the Supertonic 3 model pack on disk (identical to the Hugging Face repo).
struct SupertonicModelFiles: Sendable {
    let root: URL

    struct Entry: Sendable {
        let path: String
        /// Size published on Hugging Face (used for the progress bar only).
        let approximateBytes: Int64
    }

    static let entries: [Entry] = [
        Entry(path: "onnx/tts.json", approximateBytes: 8_253),
        Entry(path: "onnx/unicode_indexer.json", approximateBytes: 277_676),
        Entry(path: "onnx/duration_predictor.onnx", approximateBytes: 3_700_147),
        Entry(path: "onnx/text_encoder.onnx", approximateBytes: 36_416_150),
        Entry(path: "onnx/vector_estimator.onnx", approximateBytes: 256_534_781),
        Entry(path: "onnx/vocoder.onnx", approximateBytes: 101_424_195)
    ] + VoiceCatalog.supertonicStyles.map { Entry(path: "voice_styles/\($0.style).json", approximateBytes: 292_000) }

    static var totalApproximateBytes: Int64 { entries.reduce(0) { $0 + $1.approximateBytes } }

    /// Download sources, tried in order. The second one is a public mirror kept
    /// in case the upstream repository disappears.
    static let baseURLs: [URL] = [
        URL(string: "https://huggingface.co/Supertone/supertonic-3/resolve/main/")!,
        URL(string: "https://huggingface.co/lnkiai/supertonic-3-mirror/resolve/main/")!
    ]

    var config: URL { root.appendingPathComponent("onnx/tts.json") }
    var unicodeIndexer: URL { root.appendingPathComponent("onnx/unicode_indexer.json") }
    var durationPredictor: URL { root.appendingPathComponent("onnx/duration_predictor.onnx") }
    var textEncoder: URL { root.appendingPathComponent("onnx/text_encoder.onnx") }
    var vectorEstimator: URL { root.appendingPathComponent("onnx/vector_estimator.onnx") }
    var vocoder: URL { root.appendingPathComponent("onnx/vocoder.onnx") }
    func style(_ name: String) -> URL { root.appendingPathComponent("voice_styles/\(name).json") }

    /// True when every file of the pack is present and non-empty.
    var isComplete: Bool {
        let fm = FileManager.default
        return Self.entries.allSatisfy { entry in
            let path = root.appendingPathComponent(entry.path).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = attrs[.size] as? NSNumber else { return false }
            return size.int64Value > 0
        }
    }
}

/// Values read from `onnx/tts.json`.
struct SupertonicConfig: Equatable, Sendable {
    var sampleRate: Int
    var baseChunkSize: Int
    var chunkCompressFactor: Int
    var latentDim: Int

    static let fallback = SupertonicConfig(sampleRate: 44_100, baseChunkSize: 512, chunkCompressFactor: 6, latentDim: 24)

    static func load(from url: URL) throws -> SupertonicConfig {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ae = root["ae"] as? [String: Any],
              let ttl = root["ttl"] as? [String: Any] else {
            throw SupertonicError.invalidModel("tts.json illisible")
        }
        func int(_ any: Any?) -> Int? {
            if let i = any as? Int { return i }
            if let d = any as? Double { return Int(d) }
            if let n = any as? NSNumber { return n.intValue }
            return nil
        }
        guard let sr = int(ae["sample_rate"]), let chunk = int(ae["base_chunk_size"]),
              let compress = int(ttl["chunk_compress_factor"]), let latent = int(ttl["latent_dim"]) else {
            throw SupertonicError.invalidModel("tts.json incomplet")
        }
        return SupertonicConfig(sampleRate: sr, baseChunkSize: chunk, chunkCompressFactor: compress, latentDim: latent)
    }

    /// Number of audio samples represented by one latent frame.
    var samplesPerLatentFrame: Int { baseChunkSize * chunkCompressFactor }
    /// Number of latent channels fed to the vector estimator (24 × 6 = 144).
    var latentChannels: Int { latentDim * chunkCompressFactor }

    func latentLength(forSamples samples: Int) -> Int {
        max(1, (samples + samplesPerLatentFrame - 1) / samplesPerLatentFrame)
    }
}

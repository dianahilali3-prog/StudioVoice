import XCTest
@testable import DianaVoiceStudio

/// Finds the Supertonic model pack for integration tests:
/// `DIANA_MODELS_DIR` environment variable (use `TEST_RUNNER_DIANA_MODELS_DIR=…`
/// with xcodebuild), then the app's install location.
enum TestModels {
    static func locate() -> SupertonicModelFiles? {
        if let path = ProcessInfo.processInfo.environment["DIANA_MODELS_DIR"] {
            let files = SupertonicModelFiles(root: URL(fileURLWithPath: path))
            if files.isComplete { return files }
        }
        #if canImport(UIKit)
        return ModelManager.locate()
        #else
        return nil
        #endif
    }
}

/// Engine returning a 440 Hz tone whose length depends on the text.
final class ToneEngine: SpeechEngine, @unchecked Sendable {
    let sampleRate: Double = 44_100
    let nativeSpeedRange: ClosedRange<Double> = 0.7...2.0
    private let lock = NSLock()
    private(set) var requests: [EngineRequest] = []

    func prepare() async throws {}
    func unload() {}

    func synthesize(_ request: EngineRequest) async throws -> [Float] {
        lock.withLock { requests.append(request) }
        let seconds = Double(request.text.count) / 15.0 / request.speed
        let count = Int(seconds * sampleRate)
        return (0..<count).map { 0.3 * sin(2 * .pi * 440 * Float($0) / Float(sampleRate)) }
    }
}

#if canImport(AVFoundation)
import AVFoundation

final class SynthesisPipelineTests: XCTestCase {
    private func temporaryURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dvs-\(UUID().uuidString).\(ext)")
    }

    func testLongScriptIsStreamedToAMasterFile() async throws {
        let engine = ToneEngine()
        let pipeline = SynthesisPipeline(engine: engine)
        let sentence = "Voici une phrase de démonstration pour le studio de Diana. "
        let script = (0..<1_000).map { i in i % 10 == 9 ? sentence + "\n" : sentence }.joined()
        XCTAssertGreaterThan(script.count, 50_000)

        var settings = SynthesisSettings()
        settings.speed = 1.0
        let output = temporaryURL("caf")
        defer { try? FileManager.default.removeItem(at: output) }

        let result = try await pipeline.run(text: script,
                                            voice: VoiceCatalog.supertonicVoice(id: "supertonic.fr.F1")!,
                                            settings: settings, seed: 1, output: output) { _ in }
        XCTAssertGreaterThan(result.segmentCount, 100)
        XCTAssertEqual(engine.requests.count, result.segmentCount)
        let file = try AVAudioFile(forReading: output)
        XCTAssertEqual(file.fileFormat.sampleRate, 44_100)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        // ≈ 60 000 chars / 15 chars/s ≈ 66 min (plus pauses).
        XCTAssertGreaterThan(Double(file.length) / 44_100, 3_000)
    }

    func testSpeedPitchAndExport() async throws {
        let engine = ToneEngine()
        let pipeline = SynthesisPipeline(engine: engine)
        var settings = SynthesisSettings()
        settings.speed = 0.5      // native 0.7 + time-stretch
        settings.pitchSemitones = 3
        let master = temporaryURL("caf")
        defer { try? FileManager.default.removeItem(at: master) }

        let result = try await pipeline.run(text: "Bonjour, ceci est un test de vitesse lente.",
                                            voice: VoiceCatalog.supertonicVoice(id: "supertonic.fr.M1")!,
                                            settings: settings, seed: 1, output: master) { _ in }
        XCTAssertEqual(engine.requests.first?.speed, 0.7)
        XCTAssertGreaterThan(result.duration, 0)

        for format in ExportFormat.allCases {
            let url = temporaryURL(format.fileExtension)
            defer { try? FileManager.default.removeItem(at: url) }
            try AudioRenderer.convert(input: master, output: url,
                                      outputSettings: AudioRenderer.settings(for: format, wavBitDepth: 16, aacBitRate: 128_000))
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 0, "\(format) export must contain audio")
        }
    }

    func testCancellationStopsGeneration() async throws {
        let engine = ToneEngine()
        let pipeline = SynthesisPipeline(engine: engine)
        let script = String(repeating: "Une phrase parmi beaucoup d'autres phrases. \n", count: 2_000)
        let output = temporaryURL("caf")
        let task = Task {
            try await pipeline.run(text: script, voice: VoiceCatalog.supertonicVoice(id: "supertonic.fr.F1")!,
                                   settings: SynthesisSettings(), seed: 1, output: output) { _ in }
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation expected")
        } catch is CancellationError {
            // expected
        }
    }
}

/// Real on-device inference with Supertonic 3 (skipped when the models are absent).
final class SupertonicEngineIntegrationTests: XCTestCase {
    private func engine() throws -> SupertonicEngine {
        guard let files = TestModels.locate() else {
            throw XCTSkip("Supertonic models not available (set DIANA_MODELS_DIR or install them in the app)")
        }
        return SupertonicEngine(locateModel: { files })
    }

    private func request(_ text: String, _ language: VoiceLanguage, _ voiceID: String) -> EngineRequest {
        EngineRequest(text: text, language: language,
                      voice: VoiceCatalog.supertonicVoice(id: voiceID)!,
                      speed: 1.05, steps: 5, seed: 42, isCancelled: { false })
    }

    private func assertSpeech(_ samples: [Float], minSeconds: Double, file: StaticString = #filePath, line: UInt = #line) {
        let seconds = Double(samples.count) / 44_100
        XCTAssertGreaterThan(seconds, minSeconds, file: file, line: line)
        XCTAssertLessThan(seconds, 30, file: file, line: line)
        let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1))).squareRoot()
        XCTAssertGreaterThan(rms, 0.01, "Audio must not be silent", file: file, line: line)
        XCTAssertFalse(samples.contains { !$0.isFinite }, file: file, line: line)
    }

    func testFrenchVoicesBothGenders() async throws {
        let engine = try engine()
        for voice in ["supertonic.fr.F1", "supertonic.fr.M1"] {
            let samples = try await engine.synthesize(request("Bonjour, je m'appelle Diana. Bienvenue dans mon studio.", .french, voice))
            assertSpeech(samples, minSeconds: 1.5)
        }
    }

    func testArabicVoicesBothGenders() async throws {
        let engine = try engine()
        for voice in ["supertonic.ar.F1", "supertonic.ar.M1"] {
            let samples = try await engine.synthesize(request("مرحبا بكم في استوديو ديانا للتعليق الصوتي.", .arabic, voice))
            assertSpeech(samples, minSeconds: 1.5)
        }
    }

    func testDeterministicWithSameSeed() async throws {
        let engine = try engine()
        let a = try await engine.synthesize(request("Test de reproductibilité.", .french, "supertonic.fr.F2"))
        let b = try await engine.synthesize(request("Test de reproductibilité.", .french, "supertonic.fr.F2"))
        XCTAssertEqual(a.count, b.count)
    }
}
#endif

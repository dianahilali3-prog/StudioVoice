import XCTest
@testable import DianaVoiceStudio

final class AudioStitcherTests: XCTestCase {
    private let rate = 1_000.0 // small sample rate keeps the numbers readable

    private func tone(_ count: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { amplitude * sin(Float($0) * 0.3) + (($0 % 2 == 0) ? 0.2 : -0.2) }
    }

    func testPauseIsInsertedBetweenSegments() throws {
        let sink = MemorySampleSink()
        let stitcher = AudioStitcher(sink: sink, sampleRate: rate, crossfadeDuration: 0.01, trimSilence: false)
        try stitcher.append(tone(100), pauseBefore: 0)
        try stitcher.append(tone(100), pauseBefore: 0.5)
        try stitcher.finish()
        XCTAssertEqual(sink.samples.count, 100 + 500 + 100)
        XCTAssertEqual(stitcher.framesWritten, sink.samples.count)
        XCTAssertTrue(sink.samples[100..<600].allSatisfy { $0 == 0 }, "Silence expected in the pause")
    }

    func testCrossfadeOverlapsWithoutPause() throws {
        let sink = MemorySampleSink()
        let stitcher = AudioStitcher(sink: sink, sampleRate: rate, crossfadeDuration: 0.02, trimSilence: false)
        try stitcher.append(tone(100), pauseBefore: 0)
        try stitcher.append(tone(100), pauseBefore: 0)
        try stitcher.finish()
        // 20 samples overlap.
        XCTAssertEqual(sink.samples.count, 180)
    }

    func testFadesAvoidClicks() throws {
        let sink = MemorySampleSink()
        let stitcher = AudioStitcher(sink: sink, sampleRate: rate, crossfadeDuration: 0.02, trimSilence: false)
        try stitcher.append([Float](repeating: 0.8, count: 200), pauseBefore: 0)
        try stitcher.finish()
        XCTAssertLessThan(abs(sink.samples.first!), 0.1)
        XCTAssertLessThan(abs(sink.samples.last!), 0.1)
        XCTAssertEqual(sink.samples[100], 0.8, accuracy: 0.0001)
        XCTAssertEqual(stitcher.peak, 0.8, accuracy: 0.0001)
    }

    func testTrimSilenceKeepsMargin() {
        var signal = [Float](repeating: 0, count: 1_000)
        for i in 400..<600 { signal[i] = 0.5 }
        let trimmed = AudioStitcher.trimmed(signal, sampleRate: rate, margin: 0.05)
        XCTAssertEqual(trimmed.count, 200 + 2 * 50)
        XCTAssertTrue(AudioStitcher.trimmed([0, 0.001, 0], sampleRate: rate).isEmpty)
    }

    func testEmptySegmentsAreIgnored() throws {
        let sink = MemorySampleSink()
        let stitcher = AudioStitcher(sink: sink, sampleRate: rate)
        try stitcher.append([], pauseBefore: 1)
        try stitcher.finish()
        XCTAssertTrue(sink.samples.isEmpty)
    }

    func testStreamingManySegmentsHasLinearLength() throws {
        let sink = MemorySampleSink()
        let stitcher = AudioStitcher(sink: sink, sampleRate: rate, crossfadeDuration: 0.01, trimSilence: false)
        for _ in 0..<1_000 { try stitcher.append(tone(50), pauseBefore: 0.01) }
        try stitcher.finish()
        XCTAssertEqual(sink.samples.count, 1_000 * 50 + 999 * 10)
    }
}

final class SynthesisSettingsTests: XCTestCase {
    func testSpeedSplit() {
        let native = 0.7...2.0
        XCTAssertEqual(SynthesisSettings.splitSpeed(1.0, native: native).native, 1.0)
        XCTAssertEqual(SynthesisSettings.splitSpeed(1.0, native: native).residual, 1.0)
        let slow = SynthesisSettings.splitSpeed(0.5, native: native)
        XCTAssertEqual(slow.native, 0.7)
        XCTAssertEqual(slow.native * slow.residual, 0.5, accuracy: 1e-9)
        let apple = SynthesisSettings.splitSpeed(1.5, native: 1.0...1.0)
        XCTAssertEqual(apple.residual, 1.5, accuracy: 1e-9)
        XCTAssertEqual(SynthesisSettings.splitSpeed(5, native: native).native, 2.0, "Speed is clamped to 2×")
    }

    func testNormalizationGain() {
        XCTAssertEqual(SynthesisSettings.normalizationGain(forPeak: 0.891), 1, accuracy: 0.001)
        XCTAssertEqual(SynthesisSettings.normalizationGain(forPeak: 0.01), 4, "Gain is capped at +12 dB")
        XCTAssertEqual(SynthesisSettings.normalizationGain(forPeak: 0), 1)
    }

    func testTolerantDecoding() throws {
        let json = #"{"speed":1.5}"#
        let settings = try JSONDecoder().decode(SynthesisSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.speed, 1.5)
        XCTAssertEqual(settings.quality, .balanced)
        XCTAssertTrue(settings.autoDetectLanguage)
    }

    func testStatistics() {
        XCTAssertEqual(ScriptStatistics.wordCount("Bonjour  tout\nle monde"), 4)
        XCTAssertEqual(ScriptStatistics.wordCount(""), 0)
        XCTAssertEqual(ScriptStatistics.formatDuration(65), "1:05")
        XCTAssertEqual(ScriptStatistics.formatDuration(3_725), "1:02:05")
        XCTAssertEqual(ScriptStatistics.estimatedDuration(characters: 150, speed: 1), 10, accuracy: 0.001)
    }
}

final class ProjectTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dvs-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRepositoryRoundTrip() throws {
        let repository = ProjectRepository(root: root)
        var project = VoiceProject()
        project.title = "Publicité parfum"
        project.script = String(repeating: "Un script très long. ", count: 5_000)
        project.voiceID = "supertonic.ar.F2"
        project.settings.speed = 1.25
        try repository.save(project)

        let loaded = repository.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, project.id)
        XCTAssertEqual(loaded[0].script, project.script)
        XCTAssertEqual(loaded[0].settings.speed, 1.25)
        XCTAssertEqual(loaded[0].seed, project.seed)

        try repository.delete(project.id)
        XCTAssertTrue(repository.loadAll().isEmpty)
    }

    func testFingerprintTracksChanges() {
        var project = VoiceProject()
        project.script = "Bonjour."
        let first = project.currentFingerprint
        XCTAssertEqual(first, project.currentFingerprint, "Stable for identical content")
        project.settings.pitchSemitones = 2
        XCTAssertNotEqual(first, project.currentFingerprint)
        project.audioFileName = "master.caf"
        project.audioFingerprint = project.currentFingerprint
        XCTAssertTrue(project.isAudioUpToDate)
        project.script += " Encore."
        XCTAssertFalse(project.isAudioUpToDate)
    }

    func testDisplayTitleAndExportName() {
        var project = VoiceProject()
        XCTAssertEqual(project.displayTitle, "Projet sans titre")
        project.script = "Bienvenue dans le studio de Diana pour une nouvelle aventure sonore"
        XCTAssertEqual(project.displayTitle, "Bienvenue dans le studio de Diana")
        project.title = "Spot: radio/TV?"
        XCTAssertFalse(project.exportBaseName.contains("/"))
        XCTAssertFalse(project.exportBaseName.contains(":"))
        XCTAssertFalse(project.exportBaseName.contains("?"))
    }
}

import Foundation

struct GenerationProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing
        case synthesizing
        case finishing
    }

    var phase: Phase = .preparing
    var completedSegments = 0
    var totalSegments = 0
    var completedCharacters = 0
    var totalCharacters = 0
    var audioSeconds: Double = 0
    var estimatedRemaining: TimeInterval?
    /// 0…1 of the finishing (post-processing) phase.
    var finishingFraction: Double = 0

    var fraction: Double {
        switch phase {
        case .preparing: return 0
        case .synthesizing:
            guard totalCharacters > 0 else { return 0 }
            return 0.92 * Double(completedCharacters) / Double(totalCharacters)
        case .finishing: return 0.92 + 0.08 * finishingFraction
        }
    }
}

struct GenerationResult: Sendable {
    let url: URL
    let duration: TimeInterval
    let segmentCount: Int
}

/// End-to-end long-form synthesis:
/// segmentation → per-segment synthesis (streamed to disk) → stitching with
/// cross-fades → speed/pitch/loudness post-processing → lossless master file.
///
/// Memory usage does not depend on the script length: only one segment of
/// audio is in memory at any time.
struct SynthesisPipeline: Sendable {
    let engine: SpeechEngine
    var segmenter = TextSegmenter()

    func run(text: String,
             voice: Voice,
             settings: SynthesisSettings,
             seed: UInt64,
             output: URL,
             onProgress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> GenerationResult {
        var progress = GenerationProgress()
        onProgress(progress)

        let segments = segmenter.segment(text)
        guard !segments.isEmpty else { throw AudioError.emptyAudio }
        progress.totalSegments = segments.count
        progress.totalCharacters = segments.reduce(0) { $0 + $1.text.count }

        try await engine.prepare()
        try Task.checkCancellation()

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("synthesis-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let rawURL = workDir.appendingPathComponent("raw.caf")
        let stitched = try await synthesizeSegments(segments, voice: voice, settings: settings, seed: seed,
                                                    rawURL: rawURL, progress: &progress, onProgress: onProgress)
        guard stitched.frames > 0 else { throw AudioError.emptyAudio }

        // Post-processing.
        progress.phase = .finishing
        onProgress(progress)
        let speed = SynthesisSettings.splitSpeed(settings.speed, native: engine.nativeSpeedRange)
        let gain = settings.normalizeLoudness ? SynthesisSettings.normalizationGain(forPeak: stitched.peak) : 1
        if fm.fileExists(atPath: output.path) { try fm.removeItem(at: output) }
        try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let progressSnapshot = progress
        var lastReported = -1.0
        try AudioRenderer.render(input: rawURL,
                                 output: output,
                                 outputSettings: AudioRenderer.masterSettings,
                                 rate: speed.residual,
                                 pitchCents: settings.pitchSemitones * 100,
                                 gain: gain) { fraction in
            // Throttle UI updates to 1 % steps.
            guard fraction - lastReported >= 0.01 else { return }
            lastReported = fraction
            var p = progressSnapshot
            p.finishingFraction = min(1, fraction)
            onProgress(p)
        }
        try Task.checkCancellation()

        let duration = stitched.frames > 0 ? Double(stitched.frames) / engine.sampleRate / speed.residual : 0
        return GenerationResult(url: output, duration: duration, segmentCount: segments.count)
    }

    private func synthesizeSegments(_ segments: [TextSegment],
                                    voice: Voice,
                                    settings: SynthesisSettings,
                                    seed: UInt64,
                                    rawURL: URL,
                                    progress: inout GenerationProgress,
                                    onProgress: @escaping @Sendable (GenerationProgress) -> Void) async throws -> (frames: Int, peak: Float) {
        let sink = try AudioFileSink(url: rawURL, sampleRate: engine.sampleRate)
        let stitcher = AudioStitcher(sink: sink, sampleRate: engine.sampleRate, crossfadeDuration: settings.crossfade)
        let speed = SynthesisSettings.splitSpeed(settings.speed, native: engine.nativeSpeedRange)
        let start = Date()
        progress.phase = .synthesizing
        onProgress(progress)

        var pendingPause: Double = 0
        for (index, segment) in segments.enumerated() {
            try Task.checkCancellation()
            let language = LanguageDetector.language(for: segment.text, preferred: voice.language,
                                                     autoDetect: settings.autoDetectLanguage)
            let request = EngineRequest(text: segment.text,
                                        language: language,
                                        voice: voice,
                                        speed: speed.native,
                                        steps: settings.quality.rawValue,
                                        seed: seed &+ UInt64(index) &* 7_919,
                                        isCancelled: { Task.isCancelled })
            let samples = try await engine.synthesize(request)
            try stitcher.append(samples, pauseBefore: pendingPause)
            // Pause after this segment, scaled with the speed so the rhythm stays consistent.
            pendingPause = settings.pause(for: segment.pauseAfter) / max(speed.native, 0.1)

            progress.completedSegments = index + 1
            progress.completedCharacters += segment.text.count
            progress.audioSeconds = stitcher.duration
            let elapsed = Date().timeIntervalSince(start)
            if progress.completedCharacters > 0 {
                let perChar = elapsed / Double(progress.completedCharacters)
                progress.estimatedRemaining = perChar * Double(progress.totalCharacters - progress.completedCharacters)
            }
            onProgress(progress)
        }
        try stitcher.finish()
        return (stitcher.framesWritten, stitcher.peak)
    }
}

import AVFoundation
import Foundation

/// Streams mono Float32 samples into an audio file on disk.
final class AudioFileSink: AudioSampleSink {
    let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private let capacity: AVAudioFrameCount = 8_192

    /// Writes a lossless intermediate CAF (Float32).
    init(url: URL, sampleRate: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
            throw AudioError.bufferAllocation
        }
        self.buffer = buffer
    }

    func write(_ samples: ArraySlice<Float>) throws {
        var index = samples.startIndex
        while index < samples.endIndex {
            let n = min(Int(capacity), samples.endIndex - index)
            let channel = buffer.floatChannelData![0]
            samples[index..<(index + n)].withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: n)
            }
            buffer.frameLength = AVAudioFrameCount(n)
            try file.write(from: buffer)
            index += n
        }
    }
}

enum AudioError: LocalizedError {
    case bufferAllocation
    case renderFailed(String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .bufferAllocation: return "Mémoire audio insuffisante."
        case .renderFailed(let detail): return "Le traitement audio a échoué : \(detail)"
        case .emptyAudio: return "Aucun son n'a été généré. Vérifiez que le script contient du texte lisible."
        }
    }
}

/// Export formats offered to the user.
enum ExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case wav
    case m4a

    var id: String { rawValue }
    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .m4a: return "M4A (AAC)"
        }
    }

    var detail: String {
        switch self {
        case .wav: return "Qualité maximale, sans perte · idéal pour le montage"
        case .m4a: return "Fichier léger (~10× plus petit) · idéal pour partager"
        }
    }

    /// Approximate size in bytes for `duration` seconds of mono audio.
    func estimatedSize(duration: TimeInterval, wavBitDepth: Int, aacBitRate: Int) -> Int64 {
        switch self {
        case .wav: return Int64(duration * 44_100 * Double(wavBitDepth / 8)) + 44
        case .m4a: return Int64(duration * Double(aacBitRate) / 8)
        }
    }
}

/// Offline post-processing (speed residual, pitch, gain) and format conversion.
enum AudioRenderer {
    /// Renders `input` into `output` applying time-stretch / pitch / gain.
    /// The whole process is streamed block by block.
    static func render(input: URL,
                       output: URL,
                       outputSettings: [String: Any],
                       rate: Double,
                       pitchCents: Double,
                       gain: Float,
                       progress: ((Double) -> Void)? = nil) throws {
        let source = try AVAudioFile(forReading: input)
        let format = source.processingFormat
        guard source.length > 0 else { throw AudioError.emptyAudio }

        let needsTimePitch = abs(rate - 1) > 0.001 || abs(pitchCents) > 0.5
        let destination = try AVAudioFile(forWriting: output, settings: outputSettings,
                                          commonFormat: .pcmFormatFloat32, interleaved: false)

        if !needsTimePitch {
            try copy(source: source, to: destination, gain: gain, progress: progress)
            return
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(rate)
        timePitch.pitch = Float(pitchCents)
        timePitch.overlap = 16
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        let maxFrames: AVAudioFrameCount = 4_096
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrames)
        try engine.start()
        defer {
            player.stop()
            engine.stop()
        }
        player.scheduleFile(source, at: nil)
        player.play()

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw AudioError.bufferAllocation
        }
        // Extra tail so the time-pitch unit can flush its latency.
        let expected = AVAudioFramePosition(Double(source.length) / rate) + AVAudioFramePosition(format.sampleRate * 0.1)
        while engine.manualRenderingSampleTime < expected {
            let remaining = expected - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success:
                applyGain(gain, to: buffer)
                try destination.write(from: buffer)
                progress?(Double(engine.manualRenderingSampleTime) / Double(expected))
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                continue
            case .error:
                throw AudioError.renderFailed("rendu hors ligne")
            @unknown default:
                throw AudioError.renderFailed("statut inconnu")
            }
        }
    }

    /// Plain conversion (e.g. CAF → WAV/M4A) with optional gain.
    static func convert(input: URL, output: URL, outputSettings: [String: Any], progress: ((Double) -> Void)? = nil) throws {
        let source = try AVAudioFile(forReading: input)
        let destination = try AVAudioFile(forWriting: output, settings: outputSettings,
                                          commonFormat: .pcmFormatFloat32, interleaved: false)
        try copy(source: source, to: destination, gain: 1, progress: progress)
    }

    private static func copy(source: AVAudioFile, to destination: AVAudioFile, gain: Float, progress: ((Double) -> Void)?) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 16_384) else {
            throw AudioError.bufferAllocation
        }
        let total = max(1, source.length)
        while source.framePosition < source.length {
            try source.read(into: buffer)
            if buffer.frameLength == 0 { break }
            applyGain(gain, to: buffer)
            try destination.write(from: buffer)
            progress?(Double(source.framePosition) / Double(total))
        }
    }

    private static func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard abs(gain - 1) > 0.0001, let channels = buffer.floatChannelData else { return }
        for c in 0..<Int(buffer.format.channelCount) {
            let data = channels[c]
            for i in 0..<Int(buffer.frameLength) {
                // Soft safety limiter.
                data[i] = max(-0.999, min(0.999, data[i] * gain))
            }
        }
    }

    // MARK: - Output settings

    /// Master file kept in the project (lossless 24-bit CAF).
    static var masterSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    static func settings(for format: ExportFormat, wavBitDepth: Int, aacBitRate: Int) -> [String: Any] {
        switch format {
        case .wav:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: wavBitDepth,
                AVLinearPCMIsFloatKey: wavBitDepth == 32,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        case .m4a:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: aacBitRate,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        }
    }
}

/// Downsampled peak envelope used to draw the waveform.
enum WaveformAnalyzer {
    static func peaks(of url: URL, bins: Int = 160) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0, bins > 0 else { return [] }
        let framesPerBin = max(1, Int(file.length) / bins)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(min(framesPerBin, 1 << 20))) else { return [] }
        var result: [Float] = []
        result.reserveCapacity(bins)
        // Read only a slice of each bin for speed on very long files.
        let probe = min(framesPerBin, 2_048)
        for bin in 0..<bins {
            file.framePosition = AVAudioFramePosition(bin * framesPerBin)
            buffer.frameLength = 0
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(probe)) } catch { break }
            guard let data = buffer.floatChannelData?[0] else { break }
            var peak: Float = 0
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(data[i])) }
            result.append(peak)
        }
        let maxPeak = max(result.max() ?? 1, 0.0001)
        return result.map { min(1, $0 / maxPeak) }
    }
}

import AVFoundation
import Foundation

/// Secondary engine based on the voices installed with iOS (AVSpeechSynthesizer).
/// It works without downloading anything inside the app and stays 100 % offline,
/// which makes it a good fallback before the Supertonic pack is installed.
final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    let sampleRate: Double = 44_100
    /// Speed is applied by the post-processor for predictable results.
    let nativeSpeedRange: ClosedRange<Double> = 1.0...1.0

    func prepare() async throws {}
    func unload() {}

    /// Lists offline voices for French and Arabic.
    static func availableVoices() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices().compactMap { system -> Voice? in
            guard let language = VoiceLanguage.allCases.first(where: { system.language.lowercased().hasPrefix($0.localePrefix) }) else {
                return nil
            }
            if system.voiceTraits.contains(.isNoveltyVoice) { return nil }
            let gender: VoiceGender
            switch system.gender {
            case .male: gender = .male
            case .female: gender = .female
            default: gender = .female
            }
            let quality: String
            switch system.quality {
            case .premium: quality = "Premium"
            case .enhanced: quality = "Améliorée"
            default: quality = "Standard"
            }
            return Voice(id: "apple.\(system.identifier)",
                         engine: .appleSystem,
                         language: language,
                         gender: gender,
                         persona: system.name,
                         engineVoiceID: system.identifier,
                         detail: "Voix système Apple · \(quality) · \(system.language)")
        }
        .sorted { ($0.language.rawValue, $0.gender.rawValue, $0.persona) < ($1.language.rawValue, $1.gender.rawValue, $1.persona) }
    }

    func synthesize(_ request: EngineRequest) async throws -> [Float] {
        let collector = SpeechCollector(targetSampleRate: sampleRate)
        return try await collector.run(text: request.text,
                                       voiceIdentifier: request.voice.engineVoiceID,
                                       language: request.language)
    }
}

/// Collects the PCM buffers produced by `AVSpeechSynthesizer.write` and converts
/// them to mono Float32 at the app sample rate.
private final class SpeechCollector: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let targetFormat: AVAudioFormat
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var continuation: CheckedContinuation<[Float], Error>?
    private var finished = false

    init(targetSampleRate: Double) {
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetSampleRate, channels: 1, interleaved: false)!
        super.init()
    }

    func run(text: String, voiceIdentifier: String, language: VoiceLanguage) async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
                ?? AVSpeechSynthesisVoice(language: language == .french ? "fr-FR" : "ar-SA")
            utterance.prefersAssistiveTechnologySettings = false
            synthesizer.delegate = self
            synthesizer.write(utterance) { [weak self] buffer in
                guard let self else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    self.finish(nil)
                } else {
                    self.append(pcm)
                }
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Some iOS versions never deliver the empty terminal buffer.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { self.finish(nil) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(CancellationError())
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var provided = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if provided {
                status.pointee = .noDataNow
                return nil
            }
            provided = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, let channel = output.floatChannelData?[0] {
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        }
    }

    private func finish(_ error: Error?) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        let result = samples
        self.continuation = nil
        lock.unlock()
        if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result) }
    }
}

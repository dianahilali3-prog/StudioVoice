import Foundation

/// Quality presets = number of flow-matching steps of Supertonic.
enum SynthesisQuality: Int, Codable, CaseIterable, Identifiable, Sendable {
    case fast = 5
    case balanced = 8
    case high = 12
    case studio = 16

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Rapide"
        case .balanced: return "Équilibrée"
        case .high: return "Haute"
        case .studio: return "Studio"
        }
    }
}

/// Per-project voice settings (prosody + assembly).
struct SynthesisSettings: Codable, Equatable, Sendable {
    /// 0.5× … 2×.
    var speed: Double = 1.0
    /// Pitch shift in semitones (-6 … +6).
    var pitchSemitones: Double = 0
    var quality: SynthesisQuality = .balanced
    /// Silence between sentences (s).
    var sentencePause: Double = 0.30
    /// Silence at line breaks (s).
    var paragraphPause: Double = 0.70
    /// Cross-fade length between segments (s).
    var crossfade: Double = 0.02
    /// Switches to the Arabic/French voice automatically for passages in the other script.
    var autoDetectLanguage: Bool = true
    /// Normalizes the peak level to -1 dBFS.
    var normalizeLoudness: Bool = true

    static let speedRange: ClosedRange<Double> = 0.5...2.0
    static let pitchRange: ClosedRange<Double> = -6...6

    init() {}

    // Tolerant decoding: new fields get default values in old projects.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SynthesisSettings.defaultValue
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed
        pitchSemitones = try c.decodeIfPresent(Double.self, forKey: .pitchSemitones) ?? d.pitchSemitones
        quality = try c.decodeIfPresent(SynthesisQuality.self, forKey: .quality) ?? d.quality
        sentencePause = try c.decodeIfPresent(Double.self, forKey: .sentencePause) ?? d.sentencePause
        paragraphPause = try c.decodeIfPresent(Double.self, forKey: .paragraphPause) ?? d.paragraphPause
        crossfade = try c.decodeIfPresent(Double.self, forKey: .crossfade) ?? d.crossfade
        autoDetectLanguage = try c.decodeIfPresent(Bool.self, forKey: .autoDetectLanguage) ?? d.autoDetectLanguage
        normalizeLoudness = try c.decodeIfPresent(Bool.self, forKey: .normalizeLoudness) ?? d.normalizeLoudness
    }

    static let defaultValue = SynthesisSettings()

    func pause(for kind: SegmentPause) -> Double {
        switch kind {
        case .none: return 0
        case .sentence: return sentencePause
        case .paragraph: return paragraphPause
        }
    }

    /// Splits the requested speed between what the engine does natively and
    /// the residual time-stretch applied afterwards.
    static func splitSpeed(_ speed: Double, native: ClosedRange<Double>) -> (native: Double, residual: Double) {
        let clamped = min(max(speed, speedRange.lowerBound), speedRange.upperBound)
        let nativeSpeed = min(max(clamped, native.lowerBound), native.upperBound)
        return (nativeSpeed, clamped / nativeSpeed)
    }

    /// Gain bringing `peak` to -1 dBFS, limited to +12 dB.
    static func normalizationGain(forPeak peak: Float) -> Float {
        guard peak > 0.0001 else { return 1 }
        return min(0.891 / peak, 4.0)
    }
}

/// Rough speaking-time estimate (≈ 15 characters/second at 1×).
enum ScriptStatistics {
    static func wordCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
            if isSpace { inWord = false } else if !inWord { inWord = true; count += 1 }
        }
        return count
    }

    static func estimatedDuration(characters: Int, speed: Double) -> TimeInterval {
        Double(characters) / 15.0 / max(speed, 0.1)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

import Foundation

/// Very small script-based language detector used for bilingual scripts
/// (French text with Arabic passages and vice versa).
enum LanguageDetector {
    /// Returns the share (0…1) of Arabic letters among all letters of `text`.
    static func arabicRatio(_ text: String) -> Double {
        var arabic = 0
        var letters = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            if isArabic(scalar) { arabic += 1 }
        }
        guard letters > 0 else { return 0 }
        return Double(arabic) / Double(letters)
    }

    static func isArabic(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Detects the language of a segment. Returns `nil` when the text has no letters.
    static func detect(_ text: String) -> VoiceLanguage? {
        var letters = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) { letters += 1 }
        guard letters > 0 else { return nil }
        return arabicRatio(text) >= 0.5 ? .arabic : .french
    }

    /// Language actually used to synthesize `segment`.
    static func language(for segment: String, preferred: VoiceLanguage, autoDetect: Bool) -> VoiceLanguage {
        guard autoDetect, let detected = detect(segment) else { return preferred }
        return detected
    }
}

import Foundation

/// A script with its voice settings and (optionally) its generated master audio.
struct VoiceProject: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String = ""
    var script: String = ""
    var voiceID: String = VoiceCatalog.defaultVoiceID
    var settings: SynthesisSettings = SynthesisSettings()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Seed of the neural sampler, so a regeneration sounds identical.
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    /// File name of the master audio inside the project folder.
    var audioFileName: String?
    var audioDuration: TimeInterval?
    /// Hash of (script + voice + settings) used for the last generation.
    var audioFingerprint: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        script = try c.decodeIfPresent(String.self, forKey: .script) ?? ""
        voiceID = try c.decodeIfPresent(String.self, forKey: .voiceID) ?? VoiceCatalog.defaultVoiceID
        settings = try c.decodeIfPresent(SynthesisSettings.self, forKey: .settings) ?? SynthesisSettings()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        seed = try c.decodeIfPresent(UInt64.self, forKey: .seed) ?? 42
        audioFileName = try c.decodeIfPresent(String.self, forKey: .audioFileName)
        audioDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .audioDuration)
        audioFingerprint = try c.decodeIfPresent(String.self, forKey: .audioFingerprint)
    }

    /// Title shown in the library (falls back to the first words of the script).
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = script.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = firstLine.split(separator: " ").prefix(6).joined(separator: " ")
        return words.isEmpty ? "Projet sans titre" : words
    }

    var excerpt: String {
        String(script.prefix(160)).replacingOccurrences(of: "\n", with: " ")
    }

    /// Stable fingerprint of what determines the audio (FNV-1a 64).
    var currentFingerprint: String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        mix(script)
        mix(voiceID)
        mix(String(seed))
        if let data = try? JSONEncoder.sorted.encode(settings), let json = String(data: data, encoding: .utf8) { mix(json) }
        return String(hash, radix: 16)
    }

    var isAudioUpToDate: Bool { audioFileName != nil && audioFingerprint == currentFingerprint }

    /// File-system friendly name for exports.
    var exportBaseName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.newlines).union(.controlCharacters)
        let cleaned = displayTitle.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let base = cleaned.isEmpty ? "DianaVoiceStudio" : String(cleaned.prefix(60))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH'h'mm"
        return "\(base) – \(formatter.string(from: Date()))"
    }
}

extension JSONEncoder {
    static let sorted: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

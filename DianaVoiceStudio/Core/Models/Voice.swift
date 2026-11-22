import Foundation

enum VoiceLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case french = "fr"
    case arabic = "ar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .french: return "Français"
        case .arabic: return "Arabe"
        }
    }

    var flag: String {
        switch self {
        case .french: return "🇫🇷"
        case .arabic: return "🇸🇦"
        }
    }

    /// BCP-47 prefix used to match Apple system voices.
    var localePrefix: String { rawValue }

    var isRightToLeft: Bool { self == .arabic }
}

enum VoiceGender: String, Codable, CaseIterable, Identifiable, Sendable {
    case female
    case male

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: return "Femme"
        case .male: return "Homme"
        }
    }

    var symbol: String {
        switch self {
        case .female: return "figure.stand.dress"
        case .male: return "figure.stand"
        }
    }
}

enum VoiceEngineKind: String, Codable, Sendable {
    /// Supertonic 3 neural voices (ONNX Runtime, on-device, 44.1 kHz).
    case supertonic
    /// Voices installed with iOS (AVSpeechSynthesizer, offline once installed).
    case appleSystem
}

struct Voice: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier, e.g. `supertonic.fr.F1` or `apple.com.apple.voice.premium.fr-FR.Amelie`.
    let id: String
    let engine: VoiceEngineKind
    let language: VoiceLanguage
    let gender: VoiceGender
    /// Name shown to the user ("Camille").
    let persona: String
    /// Supertonic style name (`F1`…`M5`) or Apple voice identifier.
    let engineVoiceID: String
    /// Short description ("Neuronale · 44,1 kHz").
    let detail: String

    /// Clear label requested by the spec: « Français – Femme · Camille ».
    var label: String { "\(language.displayName) – \(gender.displayName) · \(persona)" }
    var shortLabel: String { "\(language.displayName) – \(gender.displayName)" }
    var initial: String { String(persona.prefix(1)).uppercased() }
}

/// Static catalog of the bundled-on-demand Supertonic voices.
enum VoiceCatalog {
    static let supertonicStyles: [(style: String, gender: VoiceGender)] = [
        ("F1", .female), ("F2", .female), ("F3", .female), ("F4", .female), ("F5", .female),
        ("M1", .male), ("M2", .male), ("M3", .male), ("M4", .male), ("M5", .male)
    ]

    private static let personas: [VoiceLanguage: [String: String]] = [
        .french: ["F1": "Camille", "F2": "Inès", "F3": "Léa", "F4": "Chloé", "F5": "Margaux",
                  "M1": "Hugo", "M2": "Lucas", "M3": "Antoine", "M4": "Julien", "M5": "Théo"],
        .arabic: ["F1": "Layla", "F2": "Yasmine", "F3": "Nour", "F4": "Salma", "F5": "Amira",
                  "M1": "Karim", "M2": "Omar", "M3": "Youssef", "M4": "Adam", "M5": "Rayan"]
    ]

    /// Native spelling used for previews.
    static let arabicNames: [String: String] = [
        "Layla": "ليلى", "Yasmine": "ياسمين", "Nour": "نور", "Salma": "سلمى", "Amira": "أميرة",
        "Karim": "كريم", "Omar": "عمر", "Youssef": "يوسف", "Adam": "آدم", "Rayan": "ريان"
    ]

    static let supertonicVoices: [Voice] = VoiceLanguage.allCases.flatMap { language in
        supertonicStyles.map { entry in
            Voice(id: "supertonic.\(language.rawValue).\(entry.style)",
                  engine: .supertonic,
                  language: language,
                  gender: entry.gender,
                  persona: personas[language]?[entry.style] ?? entry.style,
                  engineVoiceID: entry.style,
                  detail: "Neuronale Supertonic · 44,1 kHz")
        }
    }

    static let defaultVoiceID = "supertonic.fr.F1"

    static func supertonicVoice(id: String) -> Voice? {
        supertonicVoices.first { $0.id == id }
    }

    /// Sample sentence used by the « Écouter un extrait » button.
    static func previewText(for voice: Voice) -> String {
        switch voice.language {
        case .french:
            return "Bonjour, je suis \(voice.persona). Je donne vie à vos scripts, avec élégance et naturel."
        case .arabic:
            let name = arabicNames[voice.persona] ?? voice.persona
            return "مرحبًا، أنا \(name). أُحوِّل نصوصكم إلى صوتٍ طبيعيٍّ وأنيق."
        }
    }
}

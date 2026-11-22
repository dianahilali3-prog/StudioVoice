import Foundation

/// Swift port of the Supertonic text front-end (`UnicodeProcessor` in the
/// reference Python SDK). Supertonic works directly on Unicode code points:
/// no phonemizer, no espeak, which keeps the app small and fully offline.
struct SupertonicTextProcessor: Sendable {
    /// `indexer[codePoint]` = token id, or -1 if the character is unknown to the model.
    let indexer: [Int32]

    init(indexer: [Int32]) {
        self.indexer = indexer
    }

    init(indexerURL: URL) throws {
        let data = try Data(contentsOf: indexerURL)
        let values = try JSONDecoder().decode([Int32].self, from: data)
        guard !values.isEmpty else { throw SupertonicError.invalidModel("unicode_indexer.json est vide") }
        self.init(indexer: values)
    }

    /// Languages supported by Supertonic 3 (+ "na" for unknown).
    static let supportedLanguages: Set<String> = [
        "en", "ko", "ja", "ar", "bg", "cs", "da", "de", "el", "es", "et", "fi", "fr", "hi", "hr", "hu",
        "id", "it", "lt", "lv", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "tr", "uk", "vi", "na"
    ]

    private static let symbolReplacements: [(String, String)] = [
        ("\u{2013}", "-"), ("\u{2011}", "-"), ("\u{2014}", "-"), ("\u{00AF}", " "), ("_", " "),
        ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{2018}", "'"), ("\u{2019}", "'"),
        ("\u{00B4}", "'"), ("`", "'"), ("[", " "), ("]", " "), ("|", " "), ("/", " "),
        ("#", " "), ("→", " "), ("←", " ")
    ]

    private static let specialSymbols: Set<Character> = ["♥", "☆", "♡", "©", "\\"]

    private static let punctuationSpacing: [(String, String)] = [
        (" ,", ","), (" .", "."), (" !", "!"), (" ?", "?"), (" ;", ";"), (" :", ":"), (" '", "'"),
        (" ،", "،"), (" ؟", "؟"), (" ؛", "؛")
    ]

    private static let endingPunctuation: Set<Character> = [
        ".", "!", "?", ";", ":", ",", "'", "\"", ")", "]", "}", "…", "。", "」", "』", "】", "〉", "》", "›", "»",
        "؟", "،", "؛", "۔"
    ]

    private static let duplicateQuotes = try! NSRegularExpression(pattern: "([\"'])\\1+")

    static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1F600...0x1F64F, 0x1F300...0x1F5FF, 0x1F680...0x1F6FF, 0x1F700...0x1F77F,
             0x1F780...0x1F7FF, 0x1F800...0x1F8FF, 0x1F900...0x1F9FF, 0x1FA00...0x1FA6F,
             0x1FA70...0x1FAFF, 0x2600...0x26FF, 0x2700...0x27BF, 0x1F1E6...0x1F1FF:
            return true
        default:
            return false
        }
    }

    /// Normalizes text exactly like the reference implementation, then wraps it
    /// in language tags (`<fr>…</fr>`). Returns `nil` if nothing speakable remains.
    func preprocess(_ raw: String, language: String) -> String? {
        // 1. Unicode NFKD.
        var text = raw.decomposedStringWithCompatibilityMapping
        // 2. Emojis.
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !Self.isEmoji($0) })
        text = String(scalars)
        // 3. Symbols.
        for (old, new) in Self.symbolReplacements { text = text.replacingOccurrences(of: old, with: new) }
        // 4. Decorative symbols.
        text.removeAll { Self.specialSymbols.contains($0) }
        // 5. Expressions.
        let at = language == "fr" ? " arobase " : (language == "ar" ? " آت " : " at ")
        text = text.replacingOccurrences(of: "@", with: at)
        if language == "en" {
            text = text.replacingOccurrences(of: "e.g.,", with: "for example, ")
            text = text.replacingOccurrences(of: "i.e.,", with: "that is, ")
        }
        // 6. Spacing before punctuation (mirrors the reference model training data).
        for (old, new) in Self.punctuationSpacing { text = text.replacingOccurrences(of: old, with: new) }
        // 7. Duplicate quotes.
        let range = NSRange(text.startIndex..., in: text)
        text = Self.duplicateQuotes.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
        // 8. Whitespace.
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard TextSegmenter.containsSpeakableContent(text) else { return nil }
        // 9. Final punctuation.
        if let last = text.last, !Self.endingPunctuation.contains(last) { text += "." }
        // 10. Language tags.
        let lang = Self.supportedLanguages.contains(language) ? language : "na"
        return "<\(lang)>\(text)</\(lang)>"
    }

    /// Converts already-preprocessed text into model token ids. Characters
    /// unknown to the model are skipped (instead of crashing the model).
    func tokenize(_ preprocessed: String) -> [Int64] {
        var ids: [Int64] = []
        ids.reserveCapacity(preprocessed.unicodeScalars.count)
        for scalar in preprocessed.unicodeScalars {
            let value = Int(scalar.value)
            guard value < indexer.count else { continue }
            let id = indexer[value]
            if id >= 0 { ids.append(Int64(id)) }
        }
        return ids
    }

    func encode(_ text: String, language: String) -> [Int64]? {
        guard let pre = preprocess(text, language: language) else { return nil }
        let ids = tokenize(pre)
        return ids.isEmpty ? nil : ids
    }

    /// Characters of `text` that the model cannot pronounce (for UI warnings).
    func unsupportedCharacters(in text: String) -> Set<Character> {
        var result = Set<Character>()
        let replaced = Set(Self.symbolReplacements.map(\.0)).union(["@"])
        for ch in Set(text) where !ch.isWhitespace && !replaced.contains(String(ch)) && !Self.specialSymbols.contains(ch) {
            let decomposed = String(ch).decomposedStringWithCompatibilityMapping
            let ok = decomposed.unicodeScalars.allSatisfy { s in
                let v = Int(s.value)
                return v < indexer.count && indexer[v] >= 0
            }
            if !ok && !Self.isEmoji(ch.unicodeScalars.first!) { result.insert(ch) }
        }
        return result
    }
}

enum SupertonicError: LocalizedError {
    case modelNotInstalled
    case invalidModel(String)
    case runtimeUnavailable
    case inference(String)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Les voix Supertonic ne sont pas encore installées. Ouvrez l'onglet « Voix » pour les télécharger (une seule fois)."
        case .invalidModel(let detail):
            return "Modèle de voix invalide : \(detail). Supprimez puis retéléchargez les voix."
        case .runtimeUnavailable:
            return "ONNX Runtime n'est pas disponible dans cette compilation."
        case .inference(let detail):
            return "Erreur de synthèse : \(detail)"
        }
    }
}

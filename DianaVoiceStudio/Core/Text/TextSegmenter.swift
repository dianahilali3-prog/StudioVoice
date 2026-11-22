import Foundation

/// Kind of silence inserted after a segment when the audio is stitched together.
enum SegmentPause: String, Codable, Equatable, Sendable {
    /// No pause: the next segment is cross-faded directly (used when a very long
    /// sentence had to be split in the middle).
    case none
    /// Pause between two sentences of the same paragraph.
    case sentence
    /// Longer pause at the end of a paragraph / line break.
    case paragraph
}

/// One unit of text sent to the TTS engine.
struct TextSegment: Equatable, Sendable {
    var text: String
    var pauseAfter: SegmentPause
    var paragraphIndex: Int
}

/// Splits arbitrarily long scripts into engine-friendly segments.
///
/// Rules, in priority order:
/// 1. Every line break starts a new paragraph (longer pause).
/// 2. Paragraphs are cut at sentence boundaries (`. ! ? … ; ؟ ؛`), while
///    ignoring common abbreviations (« M. », « Dr. », « etc. »…), initials
///    and decimal numbers.
/// 3. Very short sentences are merged with the following one so that the
///    model always gets enough context.
/// 4. A sentence longer than `maxLength` is cut at clause punctuation
///    (`, ، : — –`), then at word boundaries, and only as a last resort
///    in the middle of a word. Those inner cuts are cross-faded without pause.
///
/// The segmenter is linear in the length of the text and never loads more than
/// one paragraph in temporary structures, so it scales to scripts of several
/// hundred thousand characters.
struct TextSegmenter: Sendable {
    /// Maximum number of characters per segment.
    var maxLength: Int = 300
    /// Sentences shorter than this are merged with the next sentence of the same paragraph.
    var shortSentenceThreshold: Int = 24

    static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", ";", "؟", "؛", "。", "！", "？", "۔"]
    static let closingCharacters: Set<Character> = ["\"", "'", "»", "”", "’", ")", "]", "}", "›", "」", "』"]
    static let unambiguousClosers: Set<Character> = ["»", "”", "›"]
    static let clauseSeparators: Set<Character> = [",", "،", ":", "—", "–"]
    /// Lower-cased abbreviations after which a period does not end a sentence.
    static let abbreviations: Set<String> = [
        "m", "mm", "mme", "mmes", "mlle", "mlles", "dr", "drs", "pr", "me", "mgr",
        "st", "ste", "cf", "ex", "p", "pp", "vol", "chap", "fig", "av", "bd",
        "env", "tél", "tel", "réf", "ref", "art", "al", "vs", "mr", "mrs", "ms",
        "jr", "sr", "inc", "ltd", "approx", "n°", "no", "éd", "ed"
    ]

    init(maxLength: Int = 300, shortSentenceThreshold: Int = 24) {
        self.maxLength = max(20, maxLength)
        self.shortSentenceThreshold = max(0, shortSentenceThreshold)
    }

    // MARK: - Public API

    func segment(_ text: String) -> [TextSegment] {
        var result: [TextSegment] = []
        var paragraphIndex = 0
        forEachParagraph(in: text) { paragraph in
            let chunks = chunks(forParagraph: paragraph)
            guard !chunks.isEmpty else { return }
            for (index, chunk) in chunks.enumerated() {
                let isLast = index == chunks.count - 1
                result.append(TextSegment(text: chunk.text,
                                          pauseAfter: isLast ? .paragraph : chunk.pauseAfter,
                                          paragraphIndex: paragraphIndex))
            }
            paragraphIndex += 1
        }
        if !result.isEmpty { result[result.count - 1].pauseAfter = .none }
        return result
    }

    // MARK: - Paragraphs

    private func forEachParagraph(in text: String, _ body: (String) -> Void) {
        // `split` on Character handles "\r\n" as a single grapheme, so we test both forms.
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" || $0 == "\u{2029}" || $0 == "\u{2028}" }) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.containsSpeakableContent(trimmed) { body(trimmed) }
        }
    }

    static func containsSpeakableContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    // MARK: - Sentences

    private struct Chunk { var text: String; var pauseAfter: SegmentPause }

    private func chunks(forParagraph paragraph: String) -> [Chunk] {
        var pieces: [Chunk] = []
        for sentence in splitSentences(paragraph) {
            if sentence.count <= maxLength {
                pieces.append(Chunk(text: sentence, pauseAfter: .sentence))
            } else {
                let parts = splitLongSentence(sentence)
                for (i, part) in parts.enumerated() {
                    pieces.append(Chunk(text: part, pauseAfter: i == parts.count - 1 ? .sentence : .none))
                }
            }
        }
        // Merge very short sentences with their neighbour.
        var merged: [Chunk] = []
        for piece in pieces {
            if var last = merged.last,
               last.pauseAfter == .sentence,
               last.text.count < shortSentenceThreshold || piece.text.count < shortSentenceThreshold,
               last.text.count + 1 + piece.text.count <= maxLength {
                last.text += " " + piece.text
                last.pauseAfter = piece.pauseAfter
                merged[merged.count - 1] = last
            } else {
                merged.append(piece)
            }
        }
        return merged.filter { Self.containsSpeakableContent($0.text) }
    }

    /// Splits a paragraph into sentences, keeping the terminal punctuation.
    func splitSentences(_ paragraph: String) -> [String] {
        let chars = Array(paragraph)
        var sentences: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            current.append(c)
            if Self.sentenceTerminators.contains(c) {
                var j = i + 1
                while j < chars.count,
                      Self.sentenceTerminators.contains(chars[j]) || Self.closingCharacters.contains(chars[j]) {
                    current.append(chars[j])
                    j += 1
                }
                // French typography: « Bonjour. » — absorb spaces followed by a closing guillemet.
                var k = j
                while k < chars.count, chars[k] == " " || chars[k] == "\u{00A0}" || chars[k] == "\u{202F}" { k += 1 }
                if k > j, k < chars.count, Self.unambiguousClosers.contains(chars[k]) {
                    current.append(contentsOf: chars[j...k])
                    j = k + 1
                }
                let followedByBoundary = j >= chars.count || chars[j].isWhitespace
                if followedByBoundary && !(c == "." && isAbbreviation(before: current, next: nextNonSpace(chars, from: j))) {
                    let sentence = current.trimmingCharacters(in: .whitespaces)
                    if !sentence.isEmpty { sentences.append(sentence) }
                    current = ""
                }
                i = j
                continue
            }
            i += 1
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }

    private func nextNonSpace(_ chars: [Character], from index: Int) -> Character? {
        var k = index
        while k < chars.count {
            if !chars[k].isWhitespace { return chars[k] }
            k += 1
        }
        return nil
    }

    /// `text` ends with "." (possibly followed by closing characters).
    private func isAbbreviation(before text: String, next: Character?) -> Bool {
        // Extract the word immediately before the final period.
        var body = Substring(text)
        while let last = body.last, Self.closingCharacters.contains(last) || last.isWhitespace { body = body.dropLast() }
        guard body.last == "." else { return false }
        body = body.dropLast()
        var word = ""
        for ch in body.reversed() {
            if ch.isLetter || ch == "°" { word.insert(ch, at: word.startIndex) } else { break }
        }
        guard !word.isEmpty else { return false }
        // A single upper-case letter is an initial ("J. K. Rowling").
        if word.count == 1, word.first?.isUppercase == true, next?.isUppercase == true { return true }
        let lower = word.lowercased()
        if lower == "etc" {
            // "etc." ends the sentence when followed by an upper-case letter or nothing.
            guard let next else { return false }
            return !next.isUppercase
        }
        return Self.abbreviations.contains(lower) && next != nil
    }

    // MARK: - Long sentences

    /// Splits a sentence that exceeds `maxLength`.
    func splitLongSentence(_ sentence: String) -> [String] {
        // 1. Clause punctuation.
        var clauses: [String] = []
        var current = ""
        for ch in sentence {
            current.append(ch)
            if Self.clauseSeparators.contains(ch) {
                clauses.append(current)
                current = ""
            }
        }
        if !current.isEmpty { clauses.append(current) }

        // 2. Pack clauses; anything still too long is cut on words.
        var units: [String] = []
        for clause in clauses {
            let trimmed = clause.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if trimmed.count <= maxLength { units.append(trimmed) } else { units.append(contentsOf: splitOnWords(trimmed)) }
        }
        return pack(units)
    }

    private func splitOnWords(_ text: String) -> [String] {
        var words: [String] = []
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if word.count <= maxLength {
                words.append(String(word))
            } else {
                // 3. Pathological "word" (URL, no spaces...): hard split.
                var start = word.startIndex
                while start < word.endIndex {
                    let end = word.index(start, offsetBy: maxLength, limitedBy: word.endIndex) ?? word.endIndex
                    words.append(String(word[start..<end]))
                    start = end
                }
            }
        }
        return pack(words)
    }

    private func pack(_ units: [String]) -> [String] {
        var out: [String] = []
        var current = ""
        var currentCount = 0
        for unit in units {
            let count = unit.count
            if current.isEmpty {
                current = unit
                currentCount = count
            } else if currentCount + 1 + count <= maxLength {
                current += " " + unit
                currentCount += 1 + count
            } else {
                out.append(current)
                current = unit
                currentCount = count
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

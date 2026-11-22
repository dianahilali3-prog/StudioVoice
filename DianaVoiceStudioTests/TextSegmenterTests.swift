import XCTest
@testable import DianaVoiceStudio

final class TextSegmenterTests: XCTestCase {
    private let segmenter = TextSegmenter(maxLength: 300)

    private func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    func testEmptyAndNonSpeakableInput() {
        XCTAssertTrue(segmenter.segment("").isEmpty)
        XCTAssertTrue(segmenter.segment("   \n\n  \t ").isEmpty)
        XCTAssertTrue(segmenter.segment("... --- !!!").isEmpty)
    }

    func testSplitsOnSentenceBoundaries() {
        let text = "Bonjour à toutes et à tous, bienvenue dans ce studio. Aujourd'hui nous parlons de voix off ! Êtes-vous prêtes pour commencer ?"
        let sentences = segmenter.splitSentences(text)
        XCTAssertEqual(sentences, [
            "Bonjour à toutes et à tous, bienvenue dans ce studio.",
            "Aujourd'hui nous parlons de voix off !",
            "Êtes-vous prêtes pour commencer ?"
        ])
    }

    func testSemicolonEndsASentence() {
        let sentences = segmenter.splitSentences("Première proposition assez longue ici; seconde proposition également longue.")
        XCTAssertEqual(sentences.count, 2)
    }

    func testAbbreviationsAndDecimalsDoNotSplit() {
        let text = "M. Dupont et Mme. Martin ont payé 3.5 euros chez le Dr. Leroy. C'est tout."
        let sentences = segmenter.splitSentences(text)
        XCTAssertEqual(sentences, ["M. Dupont et Mme. Martin ont payé 3.5 euros chez le Dr. Leroy.", "C'est tout."])
    }

    func testEtcFollowedByUppercaseEndsSentence() {
        let sentences = segmenter.splitSentences("Des pommes, des poires, etc. Ensuite nous partirons.")
        XCTAssertEqual(sentences.count, 2)
    }

    func testClosingQuotesStayWithSentence() {
        let sentences = segmenter.splitSentences("Elle a dit « Bonjour. » Puis elle est partie.")
        XCTAssertEqual(sentences.count, 2)
        XCTAssertEqual(sentences.first, "Elle a dit « Bonjour. »")
    }

    func testArabicPunctuation() {
        let text = "مرحبا بكم في الاستوديو؟ نحن سعداء جدا بوجودكم هنا اليوم. شكرا لكم على الاستماع."
        let sentences = segmenter.splitSentences(text)
        XCTAssertEqual(sentences.count, 3)
        XCTAssertTrue(sentences[0].hasSuffix("؟"))
    }

    func testLineBreaksCreateParagraphPauses() {
        let text = "Premier paragraphe avec une phrase complète.\nDeuxième paragraphe, lui aussi complet.\n\nTroisième et dernier paragraphe du script."
        let segments = segmenter.segment(text)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.paragraphIndex), [0, 1, 2])
        XCTAssertEqual(segments[0].pauseAfter, .paragraph)
        XCTAssertEqual(segments[1].pauseAfter, .paragraph)
        XCTAssertEqual(segments[2].pauseAfter, .none, "No pause after the very last segment")
    }

    func testWindowsLineEndings() {
        let segments = segmenter.segment("Ligne numéro une, assez longue.\r\nLigne numéro deux, assez longue.")
        XCTAssertEqual(segments.count, 2)
    }

    func testShortSentencesAreMerged() {
        let segments = segmenter.segment("Oui. Non. Peut-être que nous verrons cela demain matin.")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "Oui. Non. Peut-être que nous verrons cela demain matin.")
    }

    func testLongSentenceIsSplitOnClausesThenWords() {
        let clause = "une proposition relativement longue qui continue encore"
        let sentence = Array(repeating: clause, count: 20).joined(separator: ", ") + "."
        XCTAssertGreaterThan(sentence.count, 300)
        let segments = segmenter.segment(sentence)
        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertTrue(segments.allSatisfy { $0.text.count <= 300 })
        // Inner cuts of a single sentence are cross-faded without pause.
        XCTAssertTrue(segments.dropLast().allSatisfy { $0.pauseAfter == .none })
        XCTAssertEqual(words(segments.map(\.text).joined(separator: " ")), words(sentence))
    }

    func testPathologicalWordWithoutSpaces() {
        let word = String(repeating: "abcdefghij", count: 100) // 1000 chars, no space
        let segments = segmenter.segment(word)
        XCTAssertEqual(segments.count, 4)
        XCTAssertTrue(segments.allSatisfy { $0.text.count <= 300 })
        XCTAssertEqual(segments.map(\.text).joined(), word)
    }

    /// Checklist item: generation without character limit (50 000+ characters).
    func testVeryLongScriptOver50000Characters() {
        let paragraph = """
        Il était une fois, dans un studio baigné de lumière rose, une voix qui racontait des histoires. \
        Chaque phrase comptait ; chaque silence aussi. Les auditeurs écoutaient, captivés, jusqu'au dernier mot ! \
        Mais que se passerait-il si le script durait des heures ? Rien de grave : le studio découpe tout intelligemment.
        """
        let arabic = "مرحبا بكم في استوديو ديانا للتعليق الصوتي. نتمنى لكم يوما سعيدا ومليئا بالإبداع."
        var parts: [String] = []
        var total = 0
        var i = 0
        while total < 60_000 {
            let p = i % 5 == 4 ? arabic : paragraph
            parts.append(p)
            total += p.count + 1
            i += 1
        }
        let script = parts.joined(separator: "\n")
        XCTAssertGreaterThan(script.count, 50_000)

        let start = Date()
        let segments = segmenter.segment(script)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(segments.count, 100)
        XCTAssertTrue(segments.allSatisfy { $0.text.count <= 300 && !$0.text.isEmpty })
        XCTAssertEqual(words(segments.map(\.text).joined(separator: " ")), words(script), "No word may be lost or reordered")
        XCTAssertEqual(segments.last?.pauseAfter, SegmentPause.none)
        XCTAssertLessThan(elapsed, 5, "Segmentation must stay fast on very long scripts")
    }

    func testRespectsCustomMaxLength() {
        let small = TextSegmenter(maxLength: 60)
        let text = String(repeating: "Voici une phrase de test plutôt courte. ", count: 30)
        let segments = small.segment(text)
        XCTAssertTrue(segments.allSatisfy { $0.text.count <= 60 })
    }
}

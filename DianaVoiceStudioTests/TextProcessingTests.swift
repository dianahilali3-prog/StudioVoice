import XCTest
@testable import DianaVoiceStudio

final class SupertonicTextProcessorTests: XCTestCase {
    /// Indexer accepting ASCII, Latin-1 combining accents and the Arabic block.
    private func makeProcessor() -> SupertonicTextProcessor {
        var indexer = [Int32](repeating: -1, count: 0x0700)
        var next: Int32 = 0
        func allow(_ range: ClosedRange<Int>) {
            for v in range { indexer[v] = next; next += 1 }
        }
        allow(0x20...0x7E)   // printable ASCII
        allow(0x0300...0x036F) // combining diacritics (NFKD output)
        allow(0x0600...0x06FF) // Arabic
        return SupertonicTextProcessor(indexer: indexer)
    }

    func testAddsLanguageTagsAndFinalPeriod() {
        let processor = makeProcessor()
        XCTAssertEqual(processor.preprocess("Bonjour tout le monde", language: "fr"), "<fr>Bonjour tout le monde.</fr>")
        XCTAssertEqual(processor.preprocess("Déjà fini !", language: "fr")?.hasSuffix("!</fr>"), true)
    }

    func testArabicQuestionMarkIsFinalPunctuation() {
        let processor = makeProcessor()
        XCTAssertEqual(processor.preprocess("كيف حالك؟", language: "ar"), "<ar>كيف حالك؟</ar>")
    }

    func testNormalizationSteps() {
        let processor = makeProcessor()
        let out = processor.preprocess("  “Salut” — ça va ?  😀 [ok] ", language: "fr")
        XCTAssertNotNil(out)
        XCTAssertFalse(out!.contains("😀"))
        XCTAssertFalse(out!.contains("—"))
        XCTAssertFalse(out!.contains("["))
        XCTAssertFalse(out!.contains("  "))
        XCTAssertTrue(out!.contains("\"Salut\""))
        XCTAssertTrue(out!.contains("va?"), "Space before punctuation is removed like the reference implementation")
    }

    func testNFKDDecomposesAccents() {
        let processor = makeProcessor()
        let out = processor.preprocess("é", language: "fr")!
        XCTAssertTrue(out.unicodeScalars.contains { $0.value == 0x0301 })
    }

    func testEmojiOnlyTextIsNotSpeakable() {
        XCTAssertNil(makeProcessor().preprocess("😀🎉", language: "fr"))
    }

    func testTokenizeSkipsUnknownCharacters() {
        let processor = makeProcessor()
        let ids = processor.tokenize("<fr>a漢b</fr>")
        XCTAssertEqual(ids.count, "<fr>ab</fr>".count)
        XCTAssertTrue(ids.allSatisfy { $0 >= 0 })
    }

    func testUnsupportedCharactersReport() {
        let processor = makeProcessor()
        XCTAssertEqual(processor.unsupportedCharacters(in: "abc 漢"), ["漢"])
    }

    func testUnknownLanguageFallsBackToNA() {
        XCTAssertEqual(makeProcessor().preprocess("hello", language: "xx"), "<na>hello.</na>")
    }

    func testRealIndexerIfAvailable() throws {
        guard let files = TestModels.locate() else { throw XCTSkip("Supertonic models not installed") }
        let processor = try SupertonicTextProcessor(indexerURL: files.unicodeIndexer)
        XCTAssertEqual(processor.indexer.count, 65_536)
        let fr = processor.encode("Bonjour, je m'appelle Diana. Ça marche très bien !", language: "fr")
        let ar = processor.encode("مرحبا بكم في استوديو ديانا للتعليق الصوتي.", language: "ar")
        XCTAssertNotNil(fr)
        XCTAssertNotNil(ar)
        XCTAssertTrue(processor.unsupportedCharacters(in: "Àâäçéèêëîïôöùûüÿœæ ابتثجحخدذرزسشصضطظعغفقكلمنهوي").isEmpty)
    }
}

final class LanguageDetectorTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(LanguageDetector.detect("Bonjour à tous"), .french)
        XCTAssertEqual(LanguageDetector.detect("مرحبا بكم"), .arabic)
        XCTAssertNil(LanguageDetector.detect("123 !"))
        XCTAssertEqual(LanguageDetector.language(for: "مرحبا", preferred: .french, autoDetect: true), .arabic)
        XCTAssertEqual(LanguageDetector.language(for: "مرحبا", preferred: .french, autoDetect: false), .french)
        XCTAssertEqual(LanguageDetector.language(for: "...", preferred: .arabic, autoDetect: true), .arabic)
    }
}

final class VoiceCatalogTests: XCTestCase {
    func testFrenchAndArabicVoicesOfBothGenders() {
        let voices = VoiceCatalog.supertonicVoices
        XCTAssertEqual(voices.count, 20)
        for language in VoiceLanguage.allCases {
            for gender in VoiceGender.allCases {
                XCTAssertEqual(voices.filter { $0.language == language && $0.gender == gender }.count, 5,
                               "5 voices expected for \(language) \(gender)")
            }
        }
        XCTAssertEqual(Set(voices.map(\.id)).count, voices.count, "Identifiers must be unique")
        XCTAssertNotNil(VoiceCatalog.supertonicVoice(id: VoiceCatalog.defaultVoiceID))
    }

    func testClearLabels() {
        let fr = VoiceCatalog.supertonicVoice(id: "supertonic.fr.F1")!
        XCTAssertEqual(fr.label, "Français – Femme · Camille")
        let ar = VoiceCatalog.supertonicVoice(id: "supertonic.ar.M1")!
        XCTAssertEqual(ar.label, "Arabe – Homme · Karim")
        XCTAssertTrue(VoiceCatalog.previewText(for: ar).contains("كريم"))
    }

    func testModelManifestCoversAllStyles() {
        let paths = Set(SupertonicModelFiles.entries.map(\.path))
        for voice in VoiceCatalog.supertonicVoices {
            XCTAssertTrue(paths.contains("voice_styles/\(voice.engineVoiceID).json"))
        }
        XCTAssertGreaterThan(SupertonicModelFiles.totalApproximateBytes, 390_000_000)
    }
}

final class VoiceStyleTests: XCTestCase {
    func testParsesNestedTensors() throws {
        let json = """
        {"style_ttl":{"data":[[[1,2],[3,4.5]]],"dims":[1,2,2],"type":"float32"},
         "style_dp":{"data":[[[0.5]]],"dims":[1,1,1],"type":"float32"}}
        """
        let style = try VoiceStyle.parse(Data(json.utf8))
        XCTAssertEqual(style.ttl, [1, 2, 3, 4.5])
        XCTAssertEqual(style.ttlShape, [1, 2, 2])
        XCTAssertEqual(style.dp, [0.5])
    }

    func testRejectsInconsistentDims() {
        let json = #"{"style_ttl":{"data":[1,2,3],"dims":[1,2,2]},"style_dp":{"data":[1],"dims":[1]}}"#
        XCTAssertThrowsError(try VoiceStyle.parse(Data(json.utf8)))
    }

    func testSeededRandomIsDeterministicAndGaussian() {
        var a = SeededRandom(seed: 7)
        var b = SeededRandom(seed: 7)
        let x = a.gaussian(count: 20_001)
        XCTAssertEqual(x, b.gaussian(count: 20_001))
        let mean = x.reduce(0, +) / Float(x.count)
        let variance = x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(x.count)
        XCTAssertEqual(mean, 0, accuracy: 0.05)
        XCTAssertEqual(variance, 1, accuracy: 0.05)
    }

    func testConfigLatentMath() {
        let config = SupertonicConfig.fallback
        XCTAssertEqual(config.samplesPerLatentFrame, 3072)
        XCTAssertEqual(config.latentChannels, 144)
        XCTAssertEqual(config.latentLength(forSamples: 3072), 1)
        XCTAssertEqual(config.latentLength(forSamples: 3073), 2)
        XCTAssertEqual(config.latentLength(forSamples: 0), 1)
    }
}

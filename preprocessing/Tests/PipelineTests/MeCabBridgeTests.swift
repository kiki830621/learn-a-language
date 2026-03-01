import XCTest
@testable import Pipeline

final class MeCabBridgeTests: XCTestCase {

    var bridge: MeCabBridge!

    override func setUpWithError() throws {
        bridge = try MeCabBridge()
    }

    override func tearDown() {
        bridge = nil
    }

    // MARK: - Basic Tokenization

    func testTokenizesSimpleSentence() throws {
        let tokens = try bridge.tokenize("走れメロス")

        XCTAssertFalse(tokens.isEmpty, "Should produce tokens")
        // Should contain at least "走れ" and "メロス"
        let surfaces = tokens.map(\.surface)
        XCTAssertTrue(surfaces.contains("走れ") || surfaces.contains("走れ"),
                       "Should contain 走れ: got \(surfaces)")
    }

    func testTokenizesWithCorrectPOS() throws {
        let tokens = try bridge.tokenize("猫が走る")

        let cat = tokens.first { $0.surface == "猫" }
        XCTAssertNotNil(cat, "Should find 猫")
        XCTAssertEqual(cat?.pos, "名詞", "猫 should be a noun")

        let run = tokens.first { $0.surface == "走る" }
        XCTAssertNotNil(run, "Should find 走る")
        XCTAssertEqual(run?.pos, "動詞", "走る should be a verb")
    }

    // MARK: - Surface Length Handling

    func testSurfaceUsesLengthNotNullTerminator() throws {
        // MeCab's node->surface is NOT null-terminated
        // The bridge must use node->length to extract the correct surface
        let tokens = try bridge.tokenize("東京タワーは高い")

        let surfaces = tokens.map(\.surface)
        // Each surface should be a clean string, not contain trailing garbage
        for surface in surfaces {
            XCTAssertFalse(surface.isEmpty, "Surface should not be empty")
            XCTAssertFalse(surface.contains("\0"), "Surface should not contain null bytes")
        }
    }

    // MARK: - UniDic Feature Fields

    func testExtractsBaseForm() throws {
        let tokens = try bridge.tokenize("走った")

        let ran = tokens.first { $0.surface == "走っ" || $0.baseForm == "走る" }
        XCTAssertNotNil(ran, "Should find token with baseForm 走る")
        XCTAssertEqual(ran?.baseForm, "走る", "Base form of 走った should be 走る")
    }

    func testExtractsReading() throws {
        let tokens = try bridge.tokenize("漢字")

        let kanji = tokens.first { $0.surface == "漢字" }
        XCTAssertNotNil(kanji, "Should find 漢字")
        // Reading should be in katakana (UniDic convention)
        XCTAssertFalse(kanji?.reading.isEmpty ?? true, "Should have a reading")
    }

    // MARK: - Non-Interactive Tokens

    func testPunctuationIsNonInteractive() throws {
        let tokens = try bridge.tokenize("走る。")

        let period = tokens.first { $0.surface == "。" }
        XCTAssertNotNil(period, "Should find period")
        XCTAssertFalse(period?.isInteractive ?? true, "Period should be non-interactive")
    }

    // MARK: - Empty Input

    func testEmptyInputReturnsEmpty() throws {
        let tokens = try bridge.tokenize("")
        XCTAssertTrue(tokens.isEmpty, "Empty input should return empty tokens")
    }

    // MARK: - Multi-sentence

    func testMultipleSentences() throws {
        let tokens = try bridge.tokenize("猫がいる。犬もいる。")

        XCTAssertTrue(tokens.count > 4, "Should tokenize multiple sentences")
        let surfaces = tokens.map(\.surface)
        XCTAssertTrue(surfaces.contains("猫"), "Should contain 猫")
        XCTAssertTrue(surfaces.contains("犬"), "Should contain 犬")
    }
}

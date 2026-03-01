import XCTest
@testable import Pipeline

final class JMDictMatcherTests: XCTestCase {

    var matcher: JMDictMatcher!

    override func setUpWithError() throws {
        let fixtureURL = Bundle.module.url(
            forResource: "jmdict-test",
            withExtension: "json",
            subdirectory: "Fixtures"
        )
        // Fallback: load from file path relative to test source
        let url = fixtureURL ?? URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/jmdict-test.json")

        let data = try Data(contentsOf: url)
        matcher = try JMDictMatcher(jsonData: data)
    }

    override func tearDown() {
        matcher = nil
    }

    // MARK: - Loading

    func testLoadsEntriesFromJSON() {
        XCTAssertGreaterThan(matcher.entryCount, 0, "Should load entries")
    }

    // MARK: - Kanji Lookup

    func testMatchesByKanjiBaseForm() {
        let result = matcher.lookup(baseForm: "猫")

        XCTAssertNotNil(result, "Should find 猫")
        XCTAssertEqual(result?.jmdictID, 1000001)
        XCTAssertTrue(result?.definition.contains("cat") ?? false,
                      "Definition should contain 'cat': got \(result?.definition ?? "")")
    }

    func testMatchesVerbByKanji() {
        let result = matcher.lookup(baseForm: "走る")

        XCTAssertNotNil(result, "Should find 走る")
        XCTAssertEqual(result?.jmdictID, 1000002)
        XCTAssertTrue(result?.definition.contains("to run") ?? false)
    }

    func testMatchesAdjectiveByKanji() {
        let result = matcher.lookup(baseForm: "高い")

        XCTAssertNotNil(result, "Should find 高い")
        XCTAssertEqual(result?.jmdictID, 1000003)
        XCTAssertTrue(result?.definition.contains("tall") ?? false)
    }

    // MARK: - Kana Lookup

    func testMatchesByKanaWhenNoKanji() {
        let result = matcher.lookup(baseForm: "する")

        XCTAssertNotNil(result, "Should find する via kana")
        XCTAssertEqual(result?.jmdictID, 1000004)
        XCTAssertTrue(result?.definition.contains("to do") ?? false)
    }

    // MARK: - POS Mapping

    func testMapsJMDictPOSToUniDicPOS() {
        let result = matcher.lookup(baseForm: "猫")
        XCTAssertNotNil(result?.pos, "Should have POS")
        // JMDict "n" should map to something
        XCTAssertFalse(result?.pos.isEmpty ?? true)
    }

    // MARK: - Multiple Glosses

    func testCombinesMultipleGlosses() {
        let result = matcher.lookup(baseForm: "高い")

        XCTAssertNotNil(result)
        // Should join multiple glosses
        let def = result?.definition ?? ""
        XCTAssertTrue(def.contains("tall"), "Should contain 'tall'")
        XCTAssertTrue(def.contains("expensive"), "Should contain 'expensive'")
    }

    // MARK: - No Match

    func testReturnsNilForUnknownWord() {
        let result = matcher.lookup(baseForm: "存在しない語")
        XCTAssertNil(result, "Should return nil for unknown word")
    }

    // MARK: - Empty Base Form

    func testReturnsNilForEmptyBaseForm() {
        let result = matcher.lookup(baseForm: "")
        XCTAssertNil(result, "Should return nil for empty base form")
    }
}

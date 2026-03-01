import XCTest
@testable import Pipeline

final class AICorrectorTests: XCTestCase {

    // MARK: - Low Confidence Detection

    func testIdentifiesLowConfidenceTokens() {
        let tokens = [
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
            // Unknown word (stat=1 equivalent) — detected by pos "未知"
            MeCabToken(surface: "ﾊﾅ", baseForm: "ﾊﾅ", reading: "",
                      pos: "未知", posDetail: "", pronunciation: ""),
            MeCabToken(surface: "走る", baseForm: "走る", reading: "ハシル",
                      pos: "動詞", posDetail: "一般", pronunciation: "ハシル"),
        ]

        let lowConfidence = AICorrector.findLowConfidenceTokens(tokens)

        XCTAssertEqual(lowConfidence.count, 1)
        XCTAssertEqual(lowConfidence[0].surface, "ﾊﾅ")
    }

    func testNoLowConfidenceInCleanInput() {
        let tokens = [
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
            MeCabToken(surface: "が", baseForm: "が", reading: "ガ",
                      pos: "助詞", posDetail: "格助詞", pronunciation: "ガ"),
        ]

        let lowConfidence = AICorrector.findLowConfidenceTokens(tokens)
        XCTAssertTrue(lowConfidence.isEmpty)
    }

    // MARK: - Correction Merge

    func testMergesCorrectedTokens() {
        let original = [
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
            MeCabToken(surface: "ﾊﾅ", baseForm: "ﾊﾅ", reading: "",
                      pos: "未知", posDetail: "", pronunciation: ""),
        ]

        let corrections: [AICorrector.Correction] = [
            AICorrector.Correction(
                originalSurface: "ﾊﾅ",
                correctedBaseForm: "花",
                correctedReading: "ハナ",
                correctedPOS: "名詞"
            )
        ]

        let merged = AICorrector.mergeCorrections(
            tokens: original, corrections: corrections
        )

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[1].baseForm, "花")
        XCTAssertEqual(merged[1].reading, "ハナ")
        XCTAssertEqual(merged[0].baseForm, "猫", "Unaffected token should remain unchanged")
    }

    // MARK: - Skip Mode

    func testSkipModeReturnsOriginalTokens() {
        let tokens = [
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
        ]

        let result = AICorrector.skipCorrection(tokens: tokens)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].surface, "猫")
    }
}

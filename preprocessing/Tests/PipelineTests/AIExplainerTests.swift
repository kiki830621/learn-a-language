import XCTest
@testable import Pipeline

final class AIExplainerTests: XCTestCase {

    // MARK: - Verb/Adjective Filtering

    func testFiltersVerbsAndAdjectives() {
        let entries = [
            PipelineWordEntry(baseForm: "走る", pos: "動詞", reading: "ハシル"),
            PipelineWordEntry(baseForm: "猫", pos: "名詞", reading: "ネコ"),
            PipelineWordEntry(baseForm: "高い", pos: "形容詞", reading: "タカイ"),
            PipelineWordEntry(baseForm: "が", pos: "助詞", reading: "ガ"),
        ]

        let needExplanation = AIExplainer.filterNeedingExplanation(entries)

        XCTAssertEqual(needExplanation.count, 2)
        let baseForms = Set(needExplanation.map(\.baseForm))
        XCTAssertTrue(baseForms.contains("走る"))
        XCTAssertTrue(baseForms.contains("高い"))
        XCTAssertFalse(baseForms.contains("猫"), "Nouns don't need AI explanation")
    }

    func testFiltersEmptyInput() {
        let result = AIExplainer.filterNeedingExplanation([])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Explanation Format

    func testExplanationResultStructure() {
        let explanation = AIExplainer.ExplanationResult(
            baseForm: "走る",
            pos: "動詞",
            explanation: "動作を表す基本的な移動動詞。速い速度で足を動かして進む。"
        )

        XCTAssertEqual(explanation.baseForm, "走る")
        XCTAssertFalse(explanation.explanation.isEmpty)
    }

    // MARK: - Skip Mode

    func testSkipModeReturnsEmptyExplanations() {
        let entries = [
            PipelineWordEntry(baseForm: "走る", pos: "動詞", reading: "ハシル"),
        ]

        let result = AIExplainer.skipExplanation(entries: entries)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - POS Categories

    func testIdentifiesExplainablePOS() {
        XCTAssertTrue(AIExplainer.needsExplanation(pos: "動詞"))
        XCTAssertTrue(AIExplainer.needsExplanation(pos: "形容詞"))
        XCTAssertTrue(AIExplainer.needsExplanation(pos: "形状詞"))
        XCTAssertFalse(AIExplainer.needsExplanation(pos: "名詞"))
        XCTAssertFalse(AIExplainer.needsExplanation(pos: "助詞"))
        XCTAssertFalse(AIExplainer.needsExplanation(pos: "記号"))
    }
}

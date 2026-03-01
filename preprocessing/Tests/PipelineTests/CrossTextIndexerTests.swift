import XCTest
@testable import Pipeline

final class CrossTextIndexerTests: XCTestCase {

    // MARK: - Test Data

    static let work1 = CrossTextIndexer.WorkData(
        id: "work-1",
        title: "走れメロス",
        author: "太宰治",
        tokens: [
            CrossTextIndexer.TokenData(
                position: 0, surface: "走る", baseForm: "走る",
                pos: "動詞", sentenceText: "メロスは激怒した"
            ),
            CrossTextIndexer.TokenData(
                position: 1, surface: "は", baseForm: "は",
                pos: "助詞", sentenceText: nil
            ),
            CrossTextIndexer.TokenData(
                position: 2, surface: "高い", baseForm: "高い",
                pos: "形容詞", sentenceText: "空は高い"
            ),
        ]
    )

    static let work2 = CrossTextIndexer.WorkData(
        id: "work-2",
        title: "羅生門",
        author: "芥川龍之介",
        tokens: [
            CrossTextIndexer.TokenData(
                position: 0, surface: "走る", baseForm: "走る",
                pos: "動詞", sentenceText: "下人は走った"
            ),
            CrossTextIndexer.TokenData(
                position: 1, surface: "高い", baseForm: "高い",
                pos: "形容詞", sentenceText: "門は高い"
            ),
        ]
    )

    static let work3 = CrossTextIndexer.WorkData(
        id: "work-3",
        title: "坊っちゃん",
        author: "夏目漱石",
        tokens: [
            CrossTextIndexer.TokenData(
                position: 0, surface: "走る", baseForm: "走る",
                pos: "動詞", sentenceText: "坊っちゃんは走る"
            ),
        ]
    )

    // BCNF: sentence ID lookup maps "workID:tokenPosition" → sentenceID
    static let sentenceLookup: [String: String] = [
        "work-1:0": "sent-w1-0",
        "work-1:2": "sent-w1-2",
        "work-2:0": "sent-w2-0",
        "work-2:1": "sent-w2-1",
        "work-3:0": "sent-w3-0",
    ]

    // MARK: - Tests

    func testGroupsByBaseFormAndPOS() {
        let index = CrossTextIndexer.buildIndex(
            works: [Self.work1, Self.work2, Self.work3],
            sentenceIDLookup: Self.sentenceLookup
        )

        // 走る (動詞) appears in all 3 works
        let runKey = CrossTextIndexer.EntryKey(baseForm: "走る", pos: "動詞")
        let runEntries = index[runKey] ?? []
        XCTAssertEqual(runEntries.count, 3, "走る should have 3 entries")

        // 高い (形容詞) appears in 2 works
        let highKey = CrossTextIndexer.EntryKey(baseForm: "高い", pos: "形容詞")
        let highEntries = index[highKey] ?? []
        XCTAssertEqual(highEntries.count, 2, "高い should have 2 entries")

        // 助詞 should be excluded (not a verb/adj)
        let particleKey = CrossTextIndexer.EntryKey(baseForm: "は", pos: "助詞")
        XCTAssertNil(index[particleKey], "助詞 should not be indexed")
    }

    func testEntriesContainCorrectReferences() {
        let index = CrossTextIndexer.buildIndex(
            works: [Self.work1, Self.work2],
            sentenceIDLookup: Self.sentenceLookup
        )

        let runKey = CrossTextIndexer.EntryKey(baseForm: "走る", pos: "動詞")
        let entries = index[runKey] ?? []

        // BCNF: IndexEntry has workID, sentenceID, tokenPosition
        // (work_title, author, sentence text are obtained via JOINs at query time)
        let work1Entry = entries.first { $0.workID == "work-1" }
        XCTAssertNotNil(work1Entry)
        XCTAssertEqual(work1Entry?.sentenceID, "sent-w1-0")
        XCTAssertEqual(work1Entry?.tokenPosition, 0)
    }

    func testLimitsCrossTextEntries() {
        let index = CrossTextIndexer.buildIndex(
            works: [Self.work1, Self.work2, Self.work3],
            sentenceIDLookup: Self.sentenceLookup,
            maxExamplesPerEntry: 2
        )

        let runKey = CrossTextIndexer.EntryKey(baseForm: "走る", pos: "動詞")
        let runEntries = index[runKey] ?? []
        XCTAssertEqual(runEntries.count, 2, "should be limited to 2 entries")
    }

    func testEmptyWorksReturnsEmptyIndex() {
        let index = CrossTextIndexer.buildIndex(works: [])
        XCTAssertTrue(index.isEmpty)
    }

    func testOnlyIndexesVerbsAndAdjectives() {
        let nounWork = CrossTextIndexer.WorkData(
            id: "work-n",
            title: "Test",
            author: "Author",
            tokens: [
                CrossTextIndexer.TokenData(
                    position: 0, surface: "猫", baseForm: "猫",
                    pos: "名詞", sentenceText: "猫がいる"
                ),
            ]
        )

        let index = CrossTextIndexer.buildIndex(
            works: [nounWork],
            sentenceIDLookup: ["work-n:0": "sent-n-0"]
        )
        XCTAssertTrue(index.isEmpty, "nouns should not be indexed")
    }

    func testSkipsTokensWithoutSentenceText() {
        let workWithGap = CrossTextIndexer.WorkData(
            id: "work-g",
            title: "Test",
            author: "Author",
            tokens: [
                CrossTextIndexer.TokenData(
                    position: 0, surface: "走る", baseForm: "走る",
                    pos: "動詞", sentenceText: nil
                ),
            ]
        )

        let index = CrossTextIndexer.buildIndex(
            works: [workWithGap],
            sentenceIDLookup: ["work-g:0": "sent-g-0"]
        )
        XCTAssertTrue(index.isEmpty, "tokens without sentence text should be skipped")
    }

    func testSkipsTokensWithoutSentenceIDInLookup() {
        let work = CrossTextIndexer.WorkData(
            id: "work-x",
            title: "Test",
            author: "Author",
            tokens: [
                CrossTextIndexer.TokenData(
                    position: 0, surface: "走る", baseForm: "走る",
                    pos: "動詞", sentenceText: "走る"
                ),
            ]
        )

        // No sentence ID mapping provided
        let index = CrossTextIndexer.buildIndex(
            works: [work],
            sentenceIDLookup: [:]
        )
        XCTAssertTrue(index.isEmpty, "tokens without sentence ID mapping should be skipped")
    }
}

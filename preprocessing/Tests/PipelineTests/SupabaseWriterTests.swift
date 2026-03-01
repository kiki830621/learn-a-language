import XCTest
@testable import Pipeline

final class SupabaseWriterTests: XCTestCase {

    // MARK: - Work Payload Construction

    func testWorkPayloadContainsRequiredFields() {
        let work = ParsedWork(
            title: "走れメロス",
            author: "太宰治",
            aozoraURL: "https://www.aozora.gr.jp/test.html",
            lines: []
        )

        let payload = SupabaseWriter.workPayload(from: work)

        XCTAssertEqual(payload.title, "走れメロス")
        XCTAssertEqual(payload.author, "太宰治")
        XCTAssertEqual(payload.aozoraURL, "https://www.aozora.gr.jp/test.html")
        XCTAssertFalse(payload.id.isEmpty, "Should generate a UUID")
    }

    // MARK: - Token Batch Construction

    func testTokenBatchFromMeCabTokens() {
        let tokens = [
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
            MeCabToken(surface: "が", baseForm: "が", reading: "ガ",
                      pos: "助詞", posDetail: "格助詞", pronunciation: "ガ"),
            MeCabToken(surface: "走る", baseForm: "走る", reading: "ハシル",
                      pos: "動詞", posDetail: "一般", pronunciation: "ハシル"),
        ]

        // BCNF: tokenBatch no longer takes lineIndex, no longer includes
        // baseForm/pos/reading/posDetail (available via word_entry_id JOIN)
        let batch = SupabaseWriter.tokenBatch(
            from: tokens, workID: "test-work-id", sentenceID: "sent-1"
        )

        XCTAssertEqual(batch.count, 3)
        XCTAssertEqual(batch[0].surface, "猫")
        XCTAssertEqual(batch[0].workID, "test-work-id")
        XCTAssertEqual(batch[0].position, 0)
        XCTAssertEqual(batch[0].sentenceID, "sent-1")
        XCTAssertEqual(batch[1].position, 1)
        XCTAssertEqual(batch[2].position, 2)
        XCTAssertTrue(batch[0].isInteractive, "名詞 should be interactive")
        XCTAssertTrue(batch[1].isInteractive, "助詞 is interactive (learners look up particles)")
        XCTAssertTrue(batch[2].isInteractive, "動詞 should be interactive")
    }

    // MARK: - Word Entry Dedup

    func testWordEntryDedupByBaseFormAndPOS() {
        let tokens = [
            MeCabToken(surface: "走っ", baseForm: "走る", reading: "ハシッ",
                      pos: "動詞", posDetail: "一般", pronunciation: "ハシッ"),
            MeCabToken(surface: "走り", baseForm: "走る", reading: "ハシリ",
                      pos: "動詞", posDetail: "一般", pronunciation: "ハシリ"),
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
        ]

        let entries = SupabaseWriter.uniqueWordEntries(from: tokens)

        // 走る appears twice but with same baseForm+pos → dedup to 1
        XCTAssertEqual(entries.count, 2, "Should dedup by baseForm+pos")
        let baseForms = Set(entries.map(\.baseForm))
        XCTAssertTrue(baseForms.contains("走る"))
        XCTAssertTrue(baseForms.contains("猫"))
    }

    // MARK: - Non-Interactive Filtering

    func testFilterNonInteractiveFromWordEntries() {
        let tokens = [
            MeCabToken(surface: "猫", baseForm: "猫", reading: "ネコ",
                      pos: "名詞", posDetail: "普通名詞", pronunciation: "ネコ"),
            MeCabToken(surface: "。", baseForm: "。", reading: "",
                      pos: "補助記号", posDetail: "句点", pronunciation: ""),
        ]

        let entries = SupabaseWriter.uniqueWordEntries(from: tokens)

        XCTAssertEqual(entries.count, 1, "Should exclude non-interactive tokens")
        XCTAssertEqual(entries[0].baseForm, "猫")
    }

    // MARK: - Connection Config

    func testConnectionConfigFromEnvironment() {
        let config = SupabaseWriter.ConnectionConfig(
            host: "db.test.supabase.co",
            port: 5432,
            username: "testuser",
            password: "testpass",
            database: "postgres"
        )

        XCTAssertEqual(config.host, "db.test.supabase.co")
        XCTAssertEqual(config.port, 5432)
        XCTAssertEqual(config.username, "testuser")
        XCTAssertEqual(config.database, "postgres")
    }
}

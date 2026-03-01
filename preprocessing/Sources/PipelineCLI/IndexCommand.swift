import ArgumentParser
import Foundation
import Pipeline

struct Index: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Build cross-text index for all processed works (Step 7)"
    )

    @Flag(help: "Print detailed progress")
    var verbose = false

    @Option(help: "Max cross-text examples per word entry")
    var limit: Int = 5

    func run() async throws {
        print("Building cross-text index...")

        // Note: Full implementation requires Supabase connection to:
        // 1. SELECT all works (id, title, author)
        // 2. SELECT all tokens + sentences per work
        // 3. Build cross-text index via CrossTextIndexer.buildIndex()
        // 4. INSERT INTO cross_text_examples (word_entry_id, work_id, sentence_id, token_position)
        //
        // BCNF: Examples are stored in the cross_text_examples table (not JSONB).
        // For now, this prints the expected output format.
        // Actual DB queries will be added when Supabase is configured.

        print("  ⚠ DB connection not yet configured")
        print("  Use 'pipeline process' with --dry-run first to verify pipeline")
        print("")
        print("Expected workflow:")
        print("  1. Process all works with 'pipeline process <url>'")
        print("  2. Run 'pipeline index' to build cross-text examples")
        print("  3. Examples are stored in cross_text_examples table (BCNF)")
    }
}

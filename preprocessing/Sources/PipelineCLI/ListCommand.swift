import ArgumentParser
import Pipeline

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all processed works in Supabase"
    )

    @Flag(help: "Print detailed progress")
    var verbose = false

    func run() async throws {
        print("Listing processed works...")

        // Note: Full implementation requires Supabase connection to:
        // 1. SELECT id, title, author, token_count, processed_at FROM works
        //    ORDER BY processed_at DESC
        // 2. Format as aligned table output
        //
        // For now, prints the expected output format.
        // Actual DB queries will be added when Supabase is configured.

        print("  ⚠ DB connection not yet configured")
        print("")
        print("Expected output format:")
        print("ID                                    Title              Author      Tokens  Processed")
        print("────────────────────────────────────  ─────────────────  ──────────  ──────  ──────────────────")
        print("a1b2c3d4-...                          走れメロス          太宰治        8,432  2026-02-28 14:30")
    }
}

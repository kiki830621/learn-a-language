import ArgumentParser
import Foundation
import Pipeline

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all processed works in Supabase"
    )

    @Flag(help: "Print detailed progress")
    var verbose = false

    func run() async throws {
        let config = try SupabaseWriter.ConnectionConfig.fromEnvironment()
        let conn = try await SupabaseWriter.connect(config: config)
        let works = try await SupabaseWriter.listWorks(on: conn)
        try await conn.closeGracefully()

        if works.isEmpty {
            print("No works found.")
            return
        }

        // Simple table output (safe for CJK characters)
        print("Works:")
        print("")
        for work in works {
            let idShort = String(work.id.prefix(8)) + "..."
            print("  \(idShort)  \(work.title)  \(work.author)  \(work.tokenCount) tokens  \(work.processedAt)")
        }
        print("")
        print("\(works.count) works total")
    }
}

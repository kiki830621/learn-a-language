import Foundation
import PostgresNIO
import NIOCore

/// Writes pipeline output to Supabase (Postgres) using PostgresNIO.
///
/// Provides static helper methods for payload construction (testable
/// without DB connection) and async methods for actual DB writes.
public final class SupabaseWriter {

    // MARK: - Configuration

    public struct ConnectionConfig {
        public let host: String
        public let port: Int
        public let username: String
        public let password: String
        public let database: String

        public init(
            host: String,
            port: Int = 5432,
            username: String,
            password: String,
            database: String = "postgres"
        ) {
            self.host = host
            self.port = port
            self.username = username
            self.password = password
            self.database = database
        }

        /// Create config from standard PG* environment variables.
        public static func fromEnvironment() throws -> ConnectionConfig {
            guard let host = ProcessInfo.processInfo.environment["PGHOST"] else {
                throw WriterError.missingEnv("PGHOST")
            }
            guard let user = ProcessInfo.processInfo.environment["PGUSER"] else {
                throw WriterError.missingEnv("PGUSER")
            }
            guard let pass = ProcessInfo.processInfo.environment["PGPASSWORD"] else {
                throw WriterError.missingEnv("PGPASSWORD")
            }
            let port = Int(ProcessInfo.processInfo.environment["PGPORT"] ?? "5432") ?? 5432
            let db = ProcessInfo.processInfo.environment["PGDATABASE"] ?? "postgres"

            return ConnectionConfig(
                host: host, port: port, username: user,
                password: pass, database: db
            )
        }
    }

    // MARK: - Errors

    public enum WriterError: Error, LocalizedError {
        case missingEnv(String)
        case connectionFailed(String)
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .missingEnv(let key): return "Missing environment variable: \(key)"
            case .connectionFailed(let msg): return "Connection failed: \(msg)"
            case .writeFailed(let msg): return "Write failed: \(msg)"
            }
        }
    }

    // MARK: - Work Payload

    public struct WorkPayload {
        public let id: String
        public let title: String
        public let author: String
        public let aozoraURL: String
    }

    /// Build a work payload from a ParsedWork.
    public static func workPayload(from work: ParsedWork) -> WorkPayload {
        WorkPayload(
            id: UUID().uuidString.lowercased(),
            title: work.title,
            author: work.author,
            aozoraURL: work.aozoraURL
        )
    }

    // MARK: - Token Batch

    // BCNF: TokenRecord no longer carries base_form, pos, reading, pos_detail
    // (available via word_entry_id JOIN). Adds sentence_id FK.
    public struct TokenRecord {
        public let workID: String
        public let position: Int
        public let surface: String
        public let isInteractive: Bool
        public let sentenceID: String?
    }

    /// Build token records from MeCab tokens for a given work.
    public static func tokenBatch(
        from tokens: [MeCabToken],
        workID: String,
        startPosition: Int = 0,
        sentenceID: String? = nil
    ) -> [TokenRecord] {
        tokens.enumerated().map { offset, token in
            TokenRecord(
                workID: workID,
                position: startPosition + offset,
                surface: token.surface,
                isInteractive: token.isInteractive,
                sentenceID: sentenceID
            )
        }
    }

    // MARK: - Word Entry Dedup

    /// Extract unique word entries from tokens, deduplicating by baseForm+pos.
    /// Filters out non-interactive tokens (punctuation, symbols, whitespace).
    public static func uniqueWordEntries(from tokens: [MeCabToken]) -> [PipelineWordEntry] {
        var seen = Set<PipelineWordEntry>()
        var result: [PipelineWordEntry] = []

        for token in tokens where token.isInteractive {
            let entry = PipelineWordEntry(
                baseForm: token.baseForm,
                pos: token.pos,
                reading: token.reading
            )
            if !seen.contains(entry) {
                seen.insert(entry)
                result.append(entry)
            }
        }

        return result
    }
}

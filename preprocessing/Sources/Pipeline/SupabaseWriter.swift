import Foundation
import PostgresNIO
import NIOCore
import NIOSSL
import Logging

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

        public init(id: String, title: String, author: String, aozoraURL: String) {
            self.id = id
            self.title = title
            self.author = author
            self.aozoraURL = aozoraURL
        }
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
    // (available via word_entry_id JOIN). Adds sentence_id and word_entry_id FKs.
    public struct TokenRecord {
        public let workID: String
        public let position: Int
        public let surface: String
        public let isInteractive: Bool
        public let sentenceID: String?
        public let wordEntryID: String?
    }

    /// Build token records from MeCab tokens for a given work.
    /// Pass wordEntryIDMap (keyed by "baseForm\tpos") to resolve word_entry_id FKs.
    public static func tokenBatch(
        from tokens: [MeCabToken],
        workID: String,
        startPosition: Int = 0,
        sentenceID: String? = nil,
        wordEntryIDMap: [String: String] = [:]
    ) -> [TokenRecord] {
        tokens.enumerated().map { offset, token in
            let key = "\(token.baseForm)\t\(token.pos)"
            return TokenRecord(
                workID: workID,
                position: startPosition + offset,
                surface: token.surface,
                isInteractive: token.isInteractive,
                sentenceID: sentenceID,
                wordEntryID: token.isInteractive ? wordEntryIDMap[key] : nil
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

    // MARK: - DB Connection

    /// Open a PostgresConnection with TLS (required for Supabase).
    public static func connect(config: ConnectionConfig) async throws -> PostgresConnection {
        let logger = Logger(label: "pipeline.supabase-writer")

        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        let sslContext: NIOSSLContext
        do {
            sslContext = try NIOSSLContext(configuration: tlsConfig)
        } catch {
            throw WriterError.connectionFailed("Failed to create TLS context: \(error)")
        }

        let pgConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: .require(sslContext)
        )

        do {
            return try await PostgresConnection.connect(
                configuration: pgConfig,
                id: 1,
                logger: logger
            )
        } catch {
            throw WriterError.connectionFailed(String(reflecting: error))
        }
    }

    // MARK: - Work Exists Check

    /// Check if a work already exists by aozora_url. Returns the work ID if found.
    public static func workExists(aozoraURL: String, on conn: PostgresConnection) async throws -> String? {
        let rows = try await conn.query(
            "SELECT id::text FROM works WHERE aozora_url = \(aozoraURL)",
            logger: Logger(label: "pipeline.db")
        )
        for try await row in rows {
            let id = try row.decode(String.self)
            return id
        }
        return nil
    }

    // MARK: - Insert Work

    /// Insert a new work record.
    public static func insertWork(_ work: WorkPayload, on conn: PostgresConnection) async throws {
        try await conn.query(
            """
            INSERT INTO works (id, title, author, aozora_url)
            VALUES (\(work.id)::uuid, \(work.title), \(work.author), \(work.aozoraURL))
            """,
            logger: Logger(label: "pipeline.db")
        )
    }

    // MARK: - Insert Sentences

    /// Insert sentence records in batches.
    public static func insertSentences(_ sentences: [SentenceRecord], on conn: PostgresConnection) async throws {
        let batchSize = 500
        let logger = Logger(label: "pipeline.db")

        for batchStart in stride(from: 0, to: sentences.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, sentences.count)
            let batch = Array(sentences[batchStart..<batchEnd])

            var sql = "INSERT INTO sentences (id, work_id, position, text) VALUES "
            var valueParts: [String] = []
            var idx = 1
            for _ in batch {
                valueParts.append("($\(idx)::uuid, $\(idx+1)::uuid, $\(idx+2), $\(idx+3))")
                idx += 4
            }
            sql += valueParts.joined(separator: ", ")

            var query = PostgresQuery(unsafeSQL: sql, binds: PostgresBindings())
            for sentence in batch {
                query.binds.append(sentence.id)
                query.binds.append(sentence.workID)
                query.binds.append(Int32(sentence.position))
                query.binds.append(sentence.text)
            }

            try await conn.query(query, logger: logger)
        }
    }

    // MARK: - Upsert Word Entries

    /// Upsert word entries and return a mapping of "baseForm\tpos" → UUID string.
    public static func upsertWordEntries(
        _ entries: [PipelineWordEntry],
        on conn: PostgresConnection
    ) async throws -> [String: String] {
        var idMap: [String: String] = [:]
        let batchSize = 200
        let logger = Logger(label: "pipeline.db")

        for batchStart in stride(from: 0, to: entries.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, entries.count)
            let batch = Array(entries[batchStart..<batchEnd])

            var sql = """
                INSERT INTO word_entries (base_form, pos, reading, jmdict_id, jmdict_def, ai_explanation)
                VALUES\(" ")
                """
            var valueParts: [String] = []
            var idx = 1
            for _ in batch {
                valueParts.append("($\(idx), $\(idx+1), $\(idx+2), $\(idx+3), $\(idx+4), $\(idx+5))")
                idx += 6
            }
            sql += valueParts.joined(separator: ", ")
            sql += """
                \(" ")ON CONFLICT (base_form, pos) DO UPDATE SET
                    reading = EXCLUDED.reading,
                    jmdict_id = COALESCE(EXCLUDED.jmdict_id, word_entries.jmdict_id),
                    jmdict_def = COALESCE(EXCLUDED.jmdict_def, word_entries.jmdict_def),
                    ai_explanation = COALESCE(EXCLUDED.ai_explanation, word_entries.ai_explanation)
                RETURNING id::text, base_form, pos
                """

            var query = PostgresQuery(unsafeSQL: sql, binds: PostgresBindings())
            for entry in batch {
                query.binds.append(entry.baseForm)
                query.binds.append(entry.pos)
                query.binds.append(entry.reading)
                if let jid = entry.jmdictID {
                    query.binds.append(Int32(jid))
                } else {
                    query.binds.append(Optional<Int32>.none)
                }
                query.binds.append(entry.jmdictDef)
                query.binds.append(entry.aiExplanation)
            }

            let rows = try await conn.query(query, logger: logger)
            for try await row in rows {
                let (id, baseForm, pos) = try row.decode((String, String, String).self)
                let key = "\(baseForm)\t\(pos)"
                idMap[key] = id
            }
        }

        return idMap
    }

    // MARK: - Insert Tokens

    /// Batch insert token records (500 per batch).
    public static func insertTokens(
        _ tokens: [TokenRecord],
        on conn: PostgresConnection
    ) async throws {
        let batchSize = 500
        let logger = Logger(label: "pipeline.db")

        for batchStart in stride(from: 0, to: tokens.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, tokens.count)
            let batch = Array(tokens[batchStart..<batchEnd])

            var sql = """
                INSERT INTO tokens (work_id, position, surface, is_interactive, sentence_id, word_entry_id)
                VALUES\(" ")
                """
            var valueParts: [String] = []
            var idx = 1
            for _ in batch {
                valueParts.append("($\(idx)::uuid, $\(idx+1), $\(idx+2), $\(idx+3), $\(idx+4)::uuid, $\(idx+5)::uuid)")
                idx += 6
            }
            sql += valueParts.joined(separator: ", ")

            var query = PostgresQuery(unsafeSQL: sql, binds: PostgresBindings())
            for token in batch {
                query.binds.append(token.workID)
                query.binds.append(Int32(token.position))
                query.binds.append(token.surface)
                query.binds.append(token.isInteractive)
                query.binds.append(token.sentenceID)
                query.binds.append(token.wordEntryID)
            }

            try await conn.query(query, logger: logger)
        }
    }

    // MARK: - Update Token Count

    /// Update the token_count on a work record.
    public static func updateTokenCount(workID: String, count: Int, on conn: PostgresConnection) async throws {
        try await conn.query(
            "UPDATE works SET token_count = \(count) WHERE id = \(workID)::uuid",
            logger: Logger(label: "pipeline.db")
        )
    }

    // MARK: - List Works

    /// Fetch all works ordered by processed_at descending.
    public static func listWorks(on conn: PostgresConnection) async throws -> [(id: String, title: String, author: String, tokenCount: Int, processedAt: String)] {
        let rows = try await conn.query(
            """
            SELECT id::text, title, author, token_count,
                   to_char(processed_at, 'YYYY-MM-DD HH24:MI') as processed_at
            FROM works ORDER BY processed_at DESC
            """,
            logger: Logger(label: "pipeline.db")
        )

        var results: [(id: String, title: String, author: String, tokenCount: Int, processedAt: String)] = []
        for try await row in rows {
            let (id, title, author, tokenCount, processedAt) = try row.decode(
                (String, String, String, Int32, String).self
            )
            results.append((id: id, title: title, author: author, tokenCount: Int(tokenCount), processedAt: processedAt))
        }
        return results
    }
}

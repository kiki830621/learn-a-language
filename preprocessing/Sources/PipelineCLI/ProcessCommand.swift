import ArgumentParser
import Foundation
import Pipeline

struct Process: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Process a single Aozora Bunko work (Steps 1-6)"
    )

    @Argument(help: "URL or local path to an Aozora Bunko XHTML file")
    var aozoraURL: String

    @Flag(help: "Parse and tokenize without writing to Supabase")
    var dryRun = false

    @Flag(help: "Skip AI correction and explanation steps")
    var skipAI = false

    @Flag(help: "Print detailed progress for each pipeline step")
    var verbose = false

    func run() async throws {
        let startTime = Date()

        // Step 1: Parse HTML
        log("[1/6] Parsing HTML...")
        let rawData = try await fetchInput(aozoraURL)
        let work = try AozoraParser.parse(data: rawData, sourceURL: aozoraURL)
        log("       ✓ \(work.author) — \(work.title) (\(work.lines.count) lines)")

        // Step 2: Tokenize with MeCab (track sentences)
        log("[2/6] Tokenizing (MeCab)...")
        let mecab = try MeCabBridge()
        let workID = UUID().uuidString.lowercased()

        // Build sentences + per-sentence tokens
        var sentences: [SentenceRecord] = []
        var sentenceTokens: [(sentenceID: String, tokens: [MeCabToken])] = []
        var sentencePosition = 0

        for line in work.lines where !line.isHeading {
            let lineTokens = try mecab.tokenize(line.text)
            let sentence = SentenceRecord(
                workID: workID,
                position: sentencePosition,
                text: line.text
            )
            sentences.append(sentence)
            sentenceTokens.append((sentenceID: sentence.id, tokens: lineTokens))
            sentencePosition += 1
        }

        let allTokens = sentenceTokens.flatMap { $0.tokens }
        log("       ✓ \(allTokens.count) tokens, \(sentences.count) sentences")

        // Step 3: AI correction (optional)
        let correctedTokens: [MeCabToken]
        if skipAI {
            log("[3/6] AI correction...     ⏭ skipped")
            correctedTokens = AICorrector.skipCorrection(tokens: allTokens)
        } else {
            log("[3/6] AI correction...")
            let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
            if apiKey.isEmpty {
                log("       ⚠ No ANTHROPIC_API_KEY — skipping AI correction")
                correctedTokens = allTokens
            } else {
                let contextText = work.lines.prefix(5).map(\.text).joined(separator: "\n")
                correctedTokens = try await AICorrector.correctWithAI(
                    tokens: allTokens, apiKey: apiKey, contextText: contextText
                )
                let correctedCount = zip(allTokens, correctedTokens)
                    .filter { $0.baseForm != $1.baseForm }.count
                log("       ✓ \(correctedCount) tokens corrected")
            }
        }

        // Step 4: JMdict matching
        log("[4/6] JMdict matching...")
        let jmdictPath = ProcessInfo.processInfo.environment["JMDICT_PATH"]
            ?? "./data/jmdict-eng.json"
        let matcher = try JMDictMatcher(path: jmdictPath)
        var wordEntries = SupabaseWriter.uniqueWordEntries(from: correctedTokens)
        var matchCount = 0
        for i in wordEntries.indices {
            if let result = matcher.lookup(baseForm: wordEntries[i].baseForm) {
                wordEntries[i].jmdictID = result.jmdictID
                wordEntries[i].jmdictDef = result.definition
                matchCount += 1
            }
        }
        log("       ✓ \(matchCount) word entries matched")

        // Step 5: AI explanation (optional)
        if skipAI {
            log("[5/6] AI explanation...     ⏭ skipped")
        } else {
            log("[5/6] AI explanation...")
            let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
            if apiKey.isEmpty {
                log("       ⚠ No ANTHROPIC_API_KEY — skipping AI explanation")
            } else {
                let explanations = try await AIExplainer.explainWithAI(
                    entries: wordEntries, apiKey: apiKey
                )
                let explanationMap = Dictionary(
                    uniqueKeysWithValues: explanations.map { ($0.baseForm, $0.explanation) }
                )
                for i in wordEntries.indices {
                    if let explanation = explanationMap[wordEntries[i].baseForm] {
                        wordEntries[i].aiExplanation = explanation
                    }
                }
                log("       ✓ \(explanations.count) explanations generated")
            }
        }

        // Step 6: Write to Supabase
        if dryRun {
            log("[6/6] Writing to Supabase... ⏭ dry run")
            log("")
            log("Dry run summary:")
            log("  Work: \(work.title) by \(work.author)")
            log("  Tokens: \(correctedTokens.count)")
            log("  Sentences: \(sentences.count)")
            log("  Word entries: \(wordEntries.count)")
            log("  JMdict matches: \(matchCount)")
        } else {
            log("[6/6] Writing to Supabase...")
            let config = try SupabaseWriter.ConnectionConfig.fromEnvironment()
            let conn = try await SupabaseWriter.connect(config: config)

            // Check for existing work
            if let existingID = try await SupabaseWriter.workExists(aozoraURL: aozoraURL, on: conn) {
                log("       ⚠ Work already exists (id: \(existingID)), skipping")
                try await conn.close()
            } else {
                let workPayload = SupabaseWriter.WorkPayload(
                    id: workID, title: work.title,
                    author: work.author, aozoraURL: aozoraURL
                )

                // 1. Insert work
                try await SupabaseWriter.insertWork(workPayload, on: conn)

                // 2. Insert sentences
                try await SupabaseWriter.insertSentences(sentences, on: conn)

                // 3. Upsert word entries → get ID map
                let wordEntryIDMap = try await SupabaseWriter.upsertWordEntries(wordEntries, on: conn)

                // 4. Build and insert tokens (with sentence_id + word_entry_id)
                var allTokenRecords: [SupabaseWriter.TokenRecord] = []
                var correctedOffset = 0
                for st in sentenceTokens {
                    let count = st.tokens.count
                    let sentenceCorrected = Array(correctedTokens[correctedOffset..<correctedOffset + count])
                    let batch = SupabaseWriter.tokenBatch(
                        from: sentenceCorrected,
                        workID: workID,
                        startPosition: correctedOffset,
                        sentenceID: st.sentenceID,
                        wordEntryIDMap: wordEntryIDMap
                    )
                    allTokenRecords.append(contentsOf: batch)
                    correctedOffset += count
                }

                try await SupabaseWriter.insertTokens(allTokenRecords, on: conn)

                // 5. Update token count
                try await SupabaseWriter.updateTokenCount(
                    workID: workID, count: allTokenRecords.count, on: conn
                )

                log("       ✓ 1 work, \(sentences.count) sentences, \(allTokenRecords.count) tokens, \(wordEntries.count) word entries")
                try await conn.close()
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        log("")
        log("Done in \(minutes)m \(seconds)s.")
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        if verbose || !message.trimmingCharacters(in: .whitespaces).starts(with: "  ") {
            print(message)
        }
    }

    private func fetchInput(_ urlString: String) async throws -> Data {
        if FileManager.default.fileExists(atPath: urlString) {
            return try Data(contentsOf: URL(fileURLWithPath: urlString))
        }

        guard let url = URL(string: urlString) else {
            throw ValidationError("Invalid URL or file path: \(urlString)")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw ValidationError(
                "HTTP \(httpResponse.statusCode) fetching \(urlString)"
            )
        }
        return data
    }
}

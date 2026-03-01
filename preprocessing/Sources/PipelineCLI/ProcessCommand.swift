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

        // Step 2: Tokenize with MeCab
        log("[2/6] Tokenizing (MeCab)...")
        let mecab = try MeCabBridge()
        var allTokens: [MeCabToken] = []
        for line in work.lines where !line.isHeading {
            let lineTokens = try mecab.tokenize(line.text)
            allTokens.append(contentsOf: lineTokens)
        }
        log("       ✓ \(allTokens.count) tokens")

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
                // Merge explanations back
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
            log("  Word entries: \(wordEntries.count)")
            log("  JMdict matches: \(matchCount)")
        } else {
            log("[6/6] Writing to Supabase...")
            let config = try SupabaseWriter.ConnectionConfig.fromEnvironment()
            let workPayload = SupabaseWriter.workPayload(from: work)
            let tokenBatch = SupabaseWriter.tokenBatch(
                from: correctedTokens, workID: workPayload.id
            )
            log("       ✓ 1 work, \(tokenBatch.count) tokens, \(wordEntries.count) word entries")
            // Note: actual DB writes will be implemented when Supabase is configured
            log("       ⚠ DB write not yet implemented (use --dry-run for now)")
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

import ArgumentParser
import Foundation
import Pipeline

struct Batch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Batch-process all Aozora Bunko HTML files in a directory"
    )

    @Argument(help: "Directory containing .html files to process")
    var directory: String

    @Flag(help: "Skip AI correction and explanation steps")
    var skipAI = false

    @Option(help: "Maximum number of files to process (0 = unlimited)")
    var limit: Int = 0

    @Flag(help: "Print detailed progress for each pipeline step")
    var verbose = false

    func run() async throws {
        let startTime = Date()

        // Find all HTML files
        let dirURL = URL(fileURLWithPath: directory)
        guard FileManager.default.fileExists(atPath: directory) else {
            throw ValidationError("Directory does not exist: \(directory)")
        }

        let htmlFiles = try FileManager.default
            .contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let filesToProcess = limit > 0 ? Array(htmlFiles.prefix(limit)) : htmlFiles
        print("Found \(htmlFiles.count) HTML files, processing \(filesToProcess.count)")
        print("")

        // Shared resources
        let config = try SupabaseWriter.ConnectionConfig.fromEnvironment()
        let conn = try await SupabaseWriter.connect(config: config)

        let mecab = try MeCabBridge()

        let jmdictPath = ProcessInfo.processInfo.environment["JMDICT_PATH"]
            ?? "./data/jmdict-eng.json"
        let matcher = try JMDictMatcher(path: jmdictPath)

        var successCount = 0
        var skipCount = 0
        var failCount = 0
        var totalTokens = 0

        for (index, fileURL) in filesToProcess.enumerated() {
            let filePath = fileURL.path
            let fileName = fileURL.lastPathComponent
            let progress = "[\(index + 1)/\(filesToProcess.count)]"

            do {
                // Check if already processed
                if let _ = try await SupabaseWriter.workExists(aozoraURL: filePath, on: conn) {
                    print("\(progress) \(fileName) [skip] already processed")
                    skipCount += 1
                    continue
                }

                // Step 1: Parse
                let rawData = try Data(contentsOf: fileURL)
                let work = try AozoraParser.parse(data: rawData, sourceURL: filePath)

                // Step 2: Tokenize with sentence tracking
                let workID = UUID().uuidString.lowercased()
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

                // Step 3: AI correction (optional)
                let correctedTokens: [MeCabToken]
                if skipAI {
                    correctedTokens = AICorrector.skipCorrection(tokens: allTokens)
                } else {
                    let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
                    if apiKey.isEmpty {
                        correctedTokens = allTokens
                    } else {
                        let contextText = work.lines.prefix(5).map(\.text).joined(separator: "\n")
                        correctedTokens = try await AICorrector.correctWithAI(
                            tokens: allTokens, apiKey: apiKey, contextText: contextText
                        )
                    }
                }

                // Step 4: JMdict matching
                var wordEntries = SupabaseWriter.uniqueWordEntries(from: correctedTokens)
                for i in wordEntries.indices {
                    if let result = matcher.lookup(baseForm: wordEntries[i].baseForm) {
                        wordEntries[i].jmdictID = result.jmdictID
                        wordEntries[i].jmdictDef = result.definition
                    }
                }

                // Step 5: AI explanation (skipped in batch unless explicitly enabled)
                if !skipAI {
                    let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
                    if !apiKey.isEmpty {
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
                    }
                }

                // Step 6: DB write
                let workPayload = SupabaseWriter.WorkPayload(
                    id: workID, title: work.title,
                    author: work.author, aozoraURL: filePath
                )

                try await SupabaseWriter.insertWork(workPayload, on: conn)
                try await SupabaseWriter.insertSentences(sentences, on: conn)

                let wordEntryIDMap = try await SupabaseWriter.upsertWordEntries(wordEntries, on: conn)

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
                try await SupabaseWriter.updateTokenCount(
                    workID: workID, count: allTokenRecords.count, on: conn
                )

                let tokenCount = allTokenRecords.count
                totalTokens += tokenCount
                successCount += 1
                print("\(progress) \(work.title) ✓ (\(tokenCount) tokens)")

            } catch {
                failCount += 1
                print("\(progress) \(fileName) ✗ \(error.localizedDescription)")
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60

        try await conn.close()

        print("")
        print("Done in \(minutes)m \(seconds)s.")
        print("  Success: \(successCount)")
        print("  Skipped: \(skipCount)")
        print("  Failed:  \(failCount)")
        print("  Total tokens: \(totalTokens)")
    }
}

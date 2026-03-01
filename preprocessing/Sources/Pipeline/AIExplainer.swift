import Foundation

/// Generates Japanese-language explanations for verbs and adjectives
/// via Claude API.
///
/// Nouns get dictionary definitions from JMDict; verbs/adjectives
/// benefit from AI-generated contextual explanations describing
/// nuance and usage patterns.
public enum AIExplainer {

    /// POS categories that need AI explanation.
    private static let explainablePOS: Set<String> = [
        "動詞",     // verbs
        "形容詞",   // i-adjectives
        "形状詞",   // na-adjectives (UniDic)
    ]

    /// Result of an AI explanation.
    public struct ExplanationResult {
        public let baseForm: String
        public let pos: String
        public let explanation: String

        public init(baseForm: String, pos: String, explanation: String) {
            self.baseForm = baseForm
            self.pos = pos
            self.explanation = explanation
        }
    }

    /// Check if a POS category needs AI explanation.
    public static func needsExplanation(pos: String) -> Bool {
        explainablePOS.contains(pos)
    }

    /// Filter word entries to those needing AI explanation.
    public static func filterNeedingExplanation(
        _ entries: [PipelineWordEntry]
    ) -> [PipelineWordEntry] {
        entries.filter { needsExplanation(pos: $0.pos) }
    }

    /// Skip AI explanation — return empty array.
    public static func skipExplanation(
        entries: [PipelineWordEntry]
    ) -> [ExplanationResult] {
        []
    }

    /// Generate explanations via Claude API (async).
    public static func explainWithAI(
        entries: [PipelineWordEntry],
        apiKey: String
    ) async throws -> [ExplanationResult] {
        let toExplain = filterNeedingExplanation(entries)
        guard !toExplain.isEmpty else { return [] }

        // Batch in groups of 20 to avoid token limits
        var results: [ExplanationResult] = []
        let batchSize = 20
        for batchStart in stride(from: 0, to: toExplain.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, toExplain.count)
            let batch = Array(toExplain[batchStart..<batchEnd])
            let batchResults = try await callClaudeForExplanations(
                entries: batch, apiKey: apiKey
            )
            results.append(contentsOf: batchResults)
        }

        return results
    }

    // MARK: - Private

    private static func callClaudeForExplanations(
        entries: [PipelineWordEntry],
        apiKey: String
    ) async throws -> [ExplanationResult] {
        let wordList = entries
            .map { "- \($0.baseForm)（\($0.pos)）" }
            .joined(separator: "\n")

        let prompt = """
        以下の動詞・形容詞について、日本語学習者向けの簡潔な説明を日本語で書いてください。
        各語1-2文で、意味とニュアンスを伝えてください。

        \(wordList)

        JSON形式で回答:
        [{"baseForm":"基本形","explanation":"説明文"}]
        """

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return parseExplanations(from: data, entries: entries)
    }

    private static func parseExplanations(
        from data: Data,
        entries: [PipelineWordEntry]
    ) -> [ExplanationResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { return [] }

        guard let jsonStart = text.firstIndex(of: "["),
              let jsonEnd = text.lastIndex(of: "]")
        else { return [] }

        let jsonString = String(text[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]]
        else { return [] }

        let entryMap = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.baseForm, $0) }
        )

        return items.compactMap { item in
            guard let baseForm = item["baseForm"],
                  let explanation = item["explanation"],
                  let entry = entryMap[baseForm]
            else { return nil }

            return ExplanationResult(
                baseForm: baseForm,
                pos: entry.pos,
                explanation: explanation
            )
        }
    }
}

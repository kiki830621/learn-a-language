import Foundation

/// Detects low-confidence MeCab tokens and optionally corrects them
/// via Claude API.
///
/// Low-confidence indicators:
/// - POS is "未知" (unknown word)
/// - Reading is empty
/// - Surface contains half-width katakana (likely OCR artifact)
public enum AICorrector {

    /// A correction for a single token.
    public struct Correction {
        public let originalSurface: String
        public let correctedBaseForm: String
        public let correctedReading: String
        public let correctedPOS: String

        public init(
            originalSurface: String,
            correctedBaseForm: String,
            correctedReading: String,
            correctedPOS: String
        ) {
            self.originalSurface = originalSurface
            self.correctedBaseForm = correctedBaseForm
            self.correctedReading = correctedReading
            self.correctedPOS = correctedPOS
        }
    }

    /// Find tokens that MeCab couldn't confidently analyze.
    public static func findLowConfidenceTokens(
        _ tokens: [MeCabToken]
    ) -> [MeCabToken] {
        tokens.filter { token in
            token.pos == "未知"
                || (token.reading.isEmpty && token.isInteractive)
        }
    }

    /// Merge corrections back into the original token array.
    /// Tokens matching a correction's originalSurface get updated fields.
    public static func mergeCorrections(
        tokens: [MeCabToken],
        corrections: [Correction]
    ) -> [MeCabToken] {
        let correctionMap = Dictionary(
            uniqueKeysWithValues: corrections.map {
                ($0.originalSurface, $0)
            }
        )

        return tokens.map { token in
            guard let correction = correctionMap[token.surface] else {
                return token
            }
            return MeCabToken(
                surface: token.surface,
                baseForm: correction.correctedBaseForm,
                reading: correction.correctedReading,
                pos: correction.correctedPOS,
                posDetail: token.posDetail,
                pronunciation: token.pronunciation
            )
        }
    }

    /// Skip AI correction — return tokens unchanged.
    public static func skipCorrection(tokens: [MeCabToken]) -> [MeCabToken] {
        tokens
    }

    /// Call Claude API to correct low-confidence tokens (async).
    /// Pass surrounding context for better accuracy.
    public static func correctWithAI(
        tokens: [MeCabToken],
        apiKey: String,
        contextText: String
    ) async throws -> [MeCabToken] {
        let lowConfidence = findLowConfidenceTokens(tokens)
        guard !lowConfidence.isEmpty else { return tokens }

        let corrections = try await callClaudeForCorrections(
            lowConfidenceTokens: lowConfidence,
            contextText: contextText,
            apiKey: apiKey
        )

        return mergeCorrections(tokens: tokens, corrections: corrections)
    }

    // MARK: - Private

    private static func callClaudeForCorrections(
        lowConfidenceTokens: [MeCabToken],
        contextText: String,
        apiKey: String
    ) async throws -> [Correction] {
        let tokenList = lowConfidenceTokens
            .map { "- \"\($0.surface)\" (current POS: \($0.pos))" }
            .joined(separator: "\n")

        let prompt = """
        以下は青空文庫の文学作品から抽出したテキストです。MeCabが正しく解析できなかった語を修正してください。

        コンテキスト: \(contextText)

        修正が必要な語:
        \(tokenList)

        各語について以下のJSON形式で回答してください:
        [{"surface":"元の表記","baseForm":"基本形","reading":"カタカナ読み","pos":"品詞"}]

        品詞は UniDic の品詞体系に従ってください（名詞、動詞、形容詞、副詞、etc.）。
        """

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return parseCorrections(from: data, tokens: lowConfidenceTokens)
    }

    private static func parseCorrections(
        from data: Data,
        tokens: [MeCabToken]
    ) -> [Correction] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else { return [] }

        // Extract JSON array from response text
        guard let jsonStart = text.firstIndex(of: "["),
              let jsonEnd = text.lastIndex(of: "]")
        else { return [] }

        let jsonString = String(text[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]]
        else { return [] }

        return entries.compactMap { entry in
            guard let surface = entry["surface"],
                  let baseForm = entry["baseForm"],
                  let reading = entry["reading"],
                  let pos = entry["pos"]
            else { return nil }

            return Correction(
                originalSurface: surface,
                correctedBaseForm: baseForm,
                correctedReading: reading,
                correctedPOS: pos
            )
        }
    }
}

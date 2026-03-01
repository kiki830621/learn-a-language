import Foundation

/// Matches MeCab base forms against JMdict-simplified JSON entries.
///
/// Loads the full jmdict-simplified JSON into memory and indexes by
/// kanji text and kana text for O(1) lookups.
///
/// Thread safety: Immutable after init — safe to share across threads.
public final class JMDictMatcher {

    public struct MatchResult {
        public let jmdictID: Int
        public let definition: String
        public let pos: String
    }

    private let kanjiIndex: [String: JMDictEntry]
    private let kanaIndex: [String: JMDictEntry]
    public let entryCount: Int

    /// Initialize from raw JSON data (jmdict-simplified format).
    public init(jsonData: Data) throws {
        let dict = try JSONDecoder().decode(JMDictFile.self, from: jsonData)
        var kanji: [String: JMDictEntry] = [:]
        var kana: [String: JMDictEntry] = [:]

        for word in dict.words {
            // Index by all kanji forms
            for k in word.kanji {
                if kanji[k.text] == nil {
                    kanji[k.text] = word
                }
            }
            // Index by all kana forms
            for k in word.kana {
                if kana[k.text] == nil {
                    kana[k.text] = word
                }
            }
        }

        self.kanjiIndex = kanji
        self.kanaIndex = kana
        self.entryCount = dict.words.count
    }

    /// Initialize from a file path.
    public convenience init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        try self.init(jsonData: data)
    }

    /// Look up a word by its base form (MeCab field[7]).
    /// Tries kanji index first, then kana index.
    public func lookup(baseForm: String) -> MatchResult? {
        guard !baseForm.isEmpty else { return nil }

        if let entry = kanjiIndex[baseForm] {
            return makeResult(from: entry)
        }
        if let entry = kanaIndex[baseForm] {
            return makeResult(from: entry)
        }
        return nil
    }

    private func makeResult(from entry: JMDictEntry) -> MatchResult {
        let senses = entry.sense
        let definition = senses
            .flatMap(\.gloss)
            .filter { $0.lang == "eng" }
            .map(\.text)
            .joined(separator: "; ")

        let pos = senses
            .flatMap(\.partOfSpeech)
            .first ?? ""

        return MatchResult(
            jmdictID: Int(entry.id) ?? 0,
            definition: definition,
            pos: pos
        )
    }
}

// MARK: - JMdict JSON Models

private struct JMDictFile: Decodable {
    let words: [JMDictEntry]
}

private struct JMDictEntry: Decodable {
    let id: String
    let kanji: [JMDictKanji]
    let kana: [JMDictKana]
    let sense: [JMDictSense]
}

private struct JMDictKanji: Decodable {
    let common: Bool
    let text: String
}

private struct JMDictKana: Decodable {
    let common: Bool
    let text: String
}

private struct JMDictSense: Decodable {
    let partOfSpeech: [String]
    let gloss: [JMDictGloss]
}

private struct JMDictGloss: Decodable {
    let lang: String
    let text: String
}

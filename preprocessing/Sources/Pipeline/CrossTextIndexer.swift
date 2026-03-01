import Foundation

/// Builds cross-text usage examples for verbs and adjectives.
///
/// Scans all processed works, groups tokens by base_form+pos, and
/// builds an example array for each entry. The examples include
/// the sentence text, work title, author, and token position.
///
/// Only verbs (動詞), i-adjectives (形容詞), and na-adjectives (形状詞)
/// are indexed — nouns get dictionary definitions from JMDict instead.
public enum CrossTextIndexer {

    /// POS categories to index for cross-text examples.
    private static let indexablePOS: Set<String> = [
        "動詞",     // verbs
        "形容詞",   // i-adjectives
        "形状詞",   // na-adjectives (UniDic)
    ]

    // MARK: - Data Types

    /// Key for grouping: base_form + pos.
    public struct EntryKey: Hashable {
        public let baseForm: String
        public let pos: String

        public init(baseForm: String, pos: String) {
            self.baseForm = baseForm
            self.pos = pos
        }
    }

    /// Lightweight work data for indexing (no need for full ParsedWork).
    public struct WorkData {
        public let id: String
        public let title: String
        public let author: String
        public let tokens: [TokenData]

        public init(id: String, title: String, author: String, tokens: [TokenData]) {
            self.id = id
            self.title = title
            self.author = author
            self.tokens = tokens
        }
    }

    /// Lightweight token data for indexing.
    public struct TokenData {
        public let position: Int
        public let surface: String
        public let baseForm: String
        public let pos: String
        public let sentenceText: String?

        public init(
            position: Int, surface: String, baseForm: String,
            pos: String, sentenceText: String?
        ) {
            self.position = position
            self.surface = surface
            self.baseForm = baseForm
            self.pos = pos
            self.sentenceText = sentenceText
        }
    }

    // MARK: - Index Building

    /// Build cross-text index from all works.
    ///
    /// BCNF: Returns (EntryKey → [IndexEntry]) — each IndexEntry contains
    /// the work_id, sentence_id, and token_position needed for the
    /// cross_text_examples table. Denormalized fields (work_title, author,
    /// sentence text) are obtained via JOINs at query time.
    public struct IndexEntry {
        public let workID: String
        public let sentenceID: String
        public let tokenPosition: Int

        public init(workID: String, sentenceID: String, tokenPosition: Int) {
            self.workID = workID
            self.sentenceID = sentenceID
            self.tokenPosition = tokenPosition
        }
    }

    /// Build cross-text index from all works.
    ///
    /// `sentenceIDLookup` maps (workID, sentencePosition) → sentenceID
    /// so we can link tokens to their sentence records.
    public static func buildIndex(
        works: [WorkData],
        sentenceIDLookup: [String: String] = [:],
        maxExamplesPerEntry: Int = 5
    ) -> [EntryKey: [IndexEntry]] {
        var index: [EntryKey: [IndexEntry]] = [:]

        for work in works {
            for token in work.tokens {
                guard indexablePOS.contains(token.pos) else { continue }
                guard let sentence = token.sentenceText, !sentence.isEmpty else { continue }

                let key = EntryKey(baseForm: token.baseForm, pos: token.pos)

                // Look up the sentence ID from the lookup table
                let lookupKey = "\(work.id):\(token.position)"
                let sentenceID = sentenceIDLookup[lookupKey] ?? ""
                guard !sentenceID.isEmpty else { continue }

                let entry = IndexEntry(
                    workID: work.id,
                    sentenceID: sentenceID,
                    tokenPosition: token.position
                )

                var entries = index[key, default: []]
                if entries.count < maxExamplesPerEntry {
                    entries.append(entry)
                    index[key] = entries
                }
            }
        }

        return index
    }
}

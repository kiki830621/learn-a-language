import Foundation

// MARK: - Parsed from Aozora HTML

public struct ParsedWork {
    public let title: String
    public let author: String
    public let aozoraURL: String
    public let lines: [ParsedLine]

    public init(title: String, author: String, aozoraURL: String, lines: [ParsedLine]) {
        self.title = title
        self.author = author
        self.aozoraURL = aozoraURL
        self.lines = lines
    }
}

public struct ParsedLine {
    public let text: String
    public let rubyAnnotations: [RubyAnnotation]
    public let isHeading: Bool
    public let headingLevel: Int?

    public init(text: String, rubyAnnotations: [RubyAnnotation] = [], isHeading: Bool = false, headingLevel: Int? = nil) {
        self.text = text
        self.rubyAnnotations = rubyAnnotations
        self.isHeading = isHeading
        self.headingLevel = headingLevel
    }
}

public struct RubyAnnotation {
    public let base: String      // kanji text (rb)
    public let reading: String   // furigana (rt)
    public let range: Range<String.Index>  // position in line text

    public init(base: String, reading: String, range: Range<String.Index>) {
        self.base = base
        self.reading = reading
        self.range = range
    }
}

// MARK: - MeCab Tokenization Output

public struct MeCabToken {
    public let surface: String
    public let baseForm: String
    public let reading: String
    public let pos: String           // 名詞, 動詞, 形容詞, etc.
    public let posDetail: String     // 固有名詞, 自立, etc.
    public let pronunciation: String

    public var isInteractive: Bool {
        !Self.nonInteractivePOS.contains(pos)
    }

    private static let nonInteractivePOS: Set<String> = [
        "記号", "補助記号", "空白"
    ]

    public init(surface: String, baseForm: String, reading: String, pos: String, posDetail: String, pronunciation: String) {
        self.surface = surface
        self.baseForm = baseForm
        self.reading = reading
        self.pos = pos
        self.posDetail = posDetail
        self.pronunciation = pronunciation
    }
}

// MARK: - Pipeline Token (enriched, ready for DB)

public struct PipelineToken {
    public let position: Int
    public let surface: String
    public let baseForm: String
    public let reading: String
    public let pos: String
    public let posDetail: String
    public let sentenceText: String?
    public let isInteractive: Bool

    public init(position: Int, surface: String, baseForm: String, reading: String, pos: String, posDetail: String, sentenceText: String?, isInteractive: Bool) {
        self.position = position
        self.surface = surface
        self.baseForm = baseForm
        self.reading = reading
        self.pos = pos
        self.posDetail = posDetail
        self.sentenceText = sentenceText
        self.isInteractive = isInteractive
    }
}

// MARK: - Word Entry (dictionary + AI enriched)

public struct PipelineWordEntry: Hashable {
    public let baseForm: String
    public let pos: String
    public let reading: String
    public var jmdictID: Int?
    public var jmdictDef: String?
    public var aiExplanation: String?

    public init(baseForm: String, pos: String, reading: String) {
        self.baseForm = baseForm
        self.pos = pos
        self.reading = reading
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(baseForm)
        hasher.combine(pos)
    }

    public static func == (lhs: PipelineWordEntry, rhs: PipelineWordEntry) -> Bool {
        lhs.baseForm == rhs.baseForm && lhs.pos == rhs.pos
    }
}

// MARK: - Cross-Text Example (BCNF: row in cross_text_examples table)

public struct CrossTextExampleRecord {
    public let wordEntryID: String
    public let workID: String
    public let sentenceID: String
    public let tokenPosition: Int

    public init(wordEntryID: String, workID: String, sentenceID: String, tokenPosition: Int) {
        self.wordEntryID = wordEntryID
        self.workID = workID
        self.sentenceID = sentenceID
        self.tokenPosition = tokenPosition
    }
}

// MARK: - Sentence (BCNF: extracted from tokens)

public struct SentenceRecord {
    public let id: String
    public let workID: String
    public let position: Int
    public let text: String

    public init(id: String = UUID().uuidString.lowercased(), workID: String, position: Int, text: String) {
        self.id = id
        self.workID = workID
        self.position = position
        self.text = text
    }
}

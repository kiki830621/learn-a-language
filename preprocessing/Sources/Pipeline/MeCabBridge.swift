import Foundation
import CMeCab

/// Bridge to the MeCab C library for Japanese morphological analysis.
///
/// Uses UniDic dictionary with 17 feature fields:
/// - [0]: pos1 (品詞大分類) — e.g. 名詞, 動詞, 形容詞
/// - [1]: pos2 (品詞中分類)
/// - [7]: lemma (語彙素読み)
/// - [9]: pronunciation (発音)
/// - [10]: orthBase (書字形基本形)
///
/// Thread safety: One tagger per instance (not thread-safe).
/// Memory: Node data is invalidated on next parse call — copy everything immediately.
public final class MeCabBridge {

    public enum MeCabError: Error, LocalizedError {
        case initFailed(String)
        case parseFailed(String)

        public var errorDescription: String? {
            switch self {
            case .initFailed(let msg): return "MeCab init failed: \(msg)"
            case .parseFailed(let msg): return "MeCab parse failed: \(msg)"
            }
        }
    }

    private let tagger: OpaquePointer

    public init() throws {
        guard let t = mecab_new2("") else {
            let err = String(cString: mecab_strerror(nil))
            throw MeCabError.initFailed(err)
        }
        self.tagger = t
    }

    deinit {
        mecab_destroy(tagger)
    }

    /// Tokenize a Japanese text string into MeCabToken array.
    /// All data is copied out immediately (node data is transient).
    public func tokenize(_ text: String) throws -> [MeCabToken] {
        guard !text.isEmpty else { return [] }

        return try text.withCString { cStr in
            guard let node = mecab_sparse_tonode(tagger, cStr) else {
                let err = String(cString: mecab_strerror(tagger))
                throw MeCabError.parseFailed(err)
            }

            var tokens: [MeCabToken] = []
            var current: UnsafePointer<mecab_node_t>? = node

            while let n = current {
                defer {
                    if let next = n.pointee.next {
                        current = UnsafePointer(next)
                    } else {
                        current = nil
                    }
                }

                // Skip BOS/EOS nodes (stat != 0 for normal nodes... actually
                // stat == 0 is NOR (normal), 1 is UNK, 2 is BOS, 3 is EOS)
                let stat = n.pointee.stat
                guard stat == 0 || stat == 1 else { continue }

                // CRITICAL: surface is NOT null-terminated — use length field
                let length = Int(n.pointee.length)
                guard length > 0 else { continue }

                let surfaceRaw = UnsafeRawBufferPointer(
                    start: n.pointee.surface,
                    count: length
                )
                let surface = String(
                    bytes: surfaceRaw,
                    encoding: .utf8
                ) ?? ""

                // feature IS null-terminated
                let feature = String(cString: n.pointee.feature)
                let fields = feature.split(separator: ",", omittingEmptySubsequences: false)
                    .map(String.init)

                let token = MeCabToken(
                    surface: surface,
                    baseForm: safeField(fields, index: 7, fallback: surface),
                    reading: safeField(fields, index: 6, fallback: ""),
                    pos: safeField(fields, index: 0, fallback: "未知"),
                    posDetail: safeField(fields, index: 1, fallback: ""),
                    pronunciation: safeField(fields, index: 9, fallback: "")
                )

                tokens.append(token)
            }

            return tokens
        }
    }

    /// Safely extract a field from the feature array, returning fallback if
    /// index is out of bounds or the field is "*" (unknown).
    private func safeField(_ fields: [String], index: Int, fallback: String) -> String {
        guard index < fields.count else { return fallback }
        let value = fields[index]
        return value == "*" ? fallback : value
    }
}

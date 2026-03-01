import Foundation

/// Parses Aozora Bunko XHTML files into structured text with ruby annotations.
///
/// Key behaviors:
/// - Extracts text from `<div class="main_text">` only
/// - Stops at `<div class="bibliographical_information">`
/// - Extracts `<ruby><rb>base</rb><rt>reading</rt></ruby>` annotations
/// - Strips `<span class="notes">` editor annotations
/// - Splits lines on `<br />`
/// - Extracts metadata from `<meta name="DC.Title">` and `<meta name="DC.Creator">`
public enum AozoraParser {

    public enum ParseError: Error, LocalizedError {
        case invalidHTML(String)
        case missingMainText
        case missingMetadata(String)

        public var errorDescription: String? {
            switch self {
            case .invalidHTML(let detail): return "Invalid HTML: \(detail)"
            case .missingMainText: return "No <div class=\"main_text\"> found"
            case .missingMetadata(let field): return "Missing metadata: \(field)"
            }
        }
    }

    /// Parse an Aozora Bunko XHTML string (UTF-8) into a ParsedWork.
    public static func parse(html: String, sourceURL: String) throws -> ParsedWork {
        guard let data = html.data(using: .utf8) else {
            throw ParseError.invalidHTML("Cannot encode as UTF-8")
        }
        let delegate = AozoraXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let err = parser.parserError?.localizedDescription ?? "unknown"
            throw ParseError.invalidHTML(err)
        }

        // Flush any remaining line content
        delegate.flushCurrentLine()

        let title = delegate.title ?? delegate.dcTitle
        let author = delegate.author ?? delegate.dcCreator

        guard let t = title, !t.isEmpty else {
            throw ParseError.missingMetadata("title")
        }
        guard let a = author, !a.isEmpty else {
            throw ParseError.missingMetadata("author")
        }

        return ParsedWork(
            title: t,
            author: a,
            aozoraURL: sourceURL,
            lines: delegate.lines
        )
    }

    /// Parse from raw Data, auto-detecting Shift_JIS or UTF-8 encoding.
    public static func parse(data: Data, sourceURL: String) throws -> ParsedWork {
        var html: String
        // Try UTF-8 first, then Shift_JIS
        if let utf8 = String(data: data, encoding: .utf8),
           utf8.contains("<html") {
            html = utf8
        } else if let shiftJIS = String(data: data, encoding: .shiftJIS) {
            html = shiftJIS
        } else {
            throw ParseError.invalidHTML("Cannot decode as UTF-8 or Shift_JIS")
        }
        // Fix encoding declaration: after decoding to String, the actual
        // encoding is UTF-8 but the XML declaration may still say Shift_JIS.
        // XMLParser would then misinterpret the bytes.
        html = html.replacingOccurrences(
            of: "encoding=\"Shift_JIS\"",
            with: "encoding=\"UTF-8\""
        )
        return try parse(html: html, sourceURL: sourceURL)
    }
}

// MARK: - SAX Parser Delegate

private final class AozoraXMLDelegate: NSObject, XMLParserDelegate {
    var lines: [ParsedLine] = []
    var title: String?
    var author: String?
    var dcTitle: String?
    var dcCreator: String?

    // State tracking
    private var inMainText = false
    private var inBibliography = false
    private var inNotes = false
    private var inRubyRB = false
    private var inRubyRT = false
    private var inRubyRP = false
    private var inHeading = false
    private var headingLevel: Int?
    private var inMidashiAnchor = false

    // Current line accumulator
    private var currentLineText = ""
    private var currentRubyAnnotations: [RubyAnnotation] = []
    private var currentRBText = ""
    private var currentRTText = ""
    private var headingText = ""

    // Element stack for context
    private var elementStack: [String] = []

    func flushCurrentLine() {
        let trimmed = currentLineText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let headingTrimmed = headingText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || (inHeading && !headingTrimmed.isEmpty) else {
            currentLineText = ""
            currentRubyAnnotations = []
            return
        }

        if inHeading {
            lines.append(ParsedLine(
                text: headingText.trimmingCharacters(in: .whitespacesAndNewlines),
                rubyAnnotations: [],
                isHeading: true,
                headingLevel: headingLevel
            ))
            headingText = ""
            inHeading = false
            headingLevel = nil
        } else {
            lines.append(ParsedLine(
                text: trimmed,
                rubyAnnotations: currentRubyAnnotations
            ))
        }

        currentLineText = ""
        currentRubyAnnotations = []
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        elementStack.append(elementName)
        let cls = attributes["class"] ?? ""
        let name = attributes["name"] ?? ""

        switch elementName {
        case "meta":
            if name == "DC.Title" {
                dcTitle = attributes["content"]
            } else if name == "DC.Creator" {
                dcCreator = attributes["content"]
            }

        case "div":
            if cls == "main_text" {
                inMainText = true
            } else if cls == "bibliographical_information" {
                inBibliography = true
                inMainText = false
                flushCurrentLine()
            }

        case "h1":
            if cls == "title" {
                title = nil // will capture from characters
                inHeading = true
                headingLevel = 1
                headingText = ""
            }

        case "h2":
            if cls == "author" {
                author = nil
                inHeading = false // we handle author separately
            }

        case "h3" where inMainText:
            if cls.contains("midashi") {
                flushCurrentLine()
                inHeading = true
                headingLevel = 3
                headingText = ""
            }

        case "h4" where inMainText:
            if cls.contains("midashi") {
                flushCurrentLine()
                inHeading = true
                headingLevel = 4
                headingText = ""
            }

        case "h5" where inMainText:
            if cls.contains("midashi") {
                flushCurrentLine()
                inHeading = true
                headingLevel = 5
                headingText = ""
            }

        case "a":
            if cls == "midashi_anchor" {
                inMidashiAnchor = true
            }

        case "span" where inMainText:
            if cls == "notes" {
                inNotes = true
            }

        case "rb" where inMainText:
            inRubyRB = true
            currentRBText = ""

        case "rt" where inMainText:
            inRubyRT = true
            currentRTText = ""

        case "rp" where inMainText:
            inRubyRP = true

        case "br" where inMainText:
            flushCurrentLine()

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "div":
            // don't reset inMainText here; it's reset when bibliography starts
            break

        case "h1":
            if let text = title {
                // already set from characters
                _ = text
            } else {
                title = headingText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            inHeading = false
            headingLevel = nil
            headingText = ""

        case "h2":
            // author is captured via characters
            break

        case "h3", "h4", "h5" where inMainText:
            if inHeading {
                flushCurrentLine()
            }

        case "a":
            inMidashiAnchor = false

        case "span":
            if inNotes {
                inNotes = false
            }

        case "rb":
            inRubyRB = false

        case "rt":
            inRubyRT = false
            // Completed a ruby annotation — record it
            if !currentRBText.isEmpty && !currentRTText.isEmpty {
                let startIndex = currentLineText.endIndex
                currentLineText += currentRBText
                let endIndex = currentLineText.endIndex
                currentRubyAnnotations.append(RubyAnnotation(
                    base: currentRBText,
                    reading: currentRTText,
                    range: startIndex..<endIndex
                ))
            }
            currentRBText = ""
            currentRTText = ""

        case "rp":
            inRubyRP = false

        default:
            break
        }

        if elementStack.last == elementName {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // Skip if in bibliography or notes
        guard !inBibliography else { return }
        guard !inNotes else { return }
        guard !inRubyRP else { return }

        if inRubyRB {
            currentRBText += string
            return
        }

        if inRubyRT {
            currentRTText += string
            return
        }

        // Title/author capture (outside main_text)
        if !inMainText {
            if inHeading, let level = headingLevel, level == 1 {
                headingText += string
            }
            // Check if we're in h2.author
            if elementStack.contains("h2") {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    author = (author ?? "") + trimmed
                }
            }
            return
        }

        // Main text content
        if inHeading || inMidashiAnchor {
            headingText += string
        } else {
            currentLineText += string
        }
    }
}

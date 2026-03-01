import XCTest
@testable import Pipeline

final class AozoraParserTests: XCTestCase {

    // MARK: - Ruby Extraction

    func testExtractsRubyAnnotations() throws {
        let html = wrapInAozoraHTML("""
        <div class="main_text">
        <ruby><rb>山路</rb><rp>（</rp><rt>やまみち</rt><rp>）</rp></ruby>を登りながら<br />
        </div>
        """)

        let work = try AozoraParser.parse(html: html, sourceURL: "test://1")

        XCTAssertFalse(work.lines.isEmpty)
        let firstLine = work.lines[0]
        XCTAssertEqual(firstLine.text, "山路を登りながら")
        XCTAssertEqual(firstLine.rubyAnnotations.count, 1)
        XCTAssertEqual(firstLine.rubyAnnotations[0].base, "山路")
        XCTAssertEqual(firstLine.rubyAnnotations[0].reading, "やまみち")
    }

    func testExtractsMultipleRubyInOneLine() throws {
        let html = wrapInAozoraHTML("""
        <div class="main_text">
        <ruby><rb>智</rb><rp>（</rp><rt>ち</rt><rp>）</rp></ruby>に<ruby><rb>働</rb><rp>（</rp><rt>はたら</rt><rp>）</rp></ruby>けば<br />
        </div>
        """)

        let work = try AozoraParser.parse(html: html, sourceURL: "test://2")

        let line = work.lines[0]
        XCTAssertEqual(line.text, "智に働けば")
        XCTAssertEqual(line.rubyAnnotations.count, 2)
        XCTAssertEqual(line.rubyAnnotations[0].base, "智")
        XCTAssertEqual(line.rubyAnnotations[0].reading, "ち")
        XCTAssertEqual(line.rubyAnnotations[1].base, "働")
        XCTAssertEqual(line.rubyAnnotations[1].reading, "はたら")
    }

    // MARK: - Main Text Isolation

    func testExtractsOnlyMainText() throws {
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">
        <head>
        <meta name="DC.Title" content="テスト作品" />
        <meta name="DC.Creator" content="テスト著者" />
        <title>テスト著者 テスト作品</title>
        </head>
        <body>
        <div class="metadata">
        <h1 class="title">テスト作品</h1>
        <h2 class="author">テスト著者</h2>
        </div>
        <div class="main_text">
        本文の内容です。<br />
        </div>
        <div class="bibliographical_information">
        底本情報<br />
        </div>
        </body>
        </html>
        """

        let work = try AozoraParser.parse(html: html, sourceURL: "test://3")

        XCTAssertEqual(work.title, "テスト作品")
        XCTAssertEqual(work.author, "テスト著者")
        let allText = work.lines.map(\.text).joined()
        XCTAssertTrue(allText.contains("本文の内容です。"))
        XCTAssertFalse(allText.contains("底本情報"))
    }

    // MARK: - Notes Stripping

    func testStripsEditorNotes() throws {
        let html = wrapInAozoraHTML("""
        <div class="main_text">
        テスト<span class="notes">［＃改ページ］</span>テキスト<br />
        </div>
        """)

        let work = try AozoraParser.parse(html: html, sourceURL: "test://4")

        let line = work.lines[0]
        XCTAssertEqual(line.text, "テストテキスト")
        XCTAssertFalse(line.text.contains("改ページ"))
    }

    // MARK: - Metadata Extraction

    func testExtractsMetadata() throws {
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">
        <head>
        <meta name="DC.Title" content="草枕" />
        <meta name="DC.Creator" content="夏目漱石" />
        <title>夏目漱石 草枕</title>
        </head>
        <body>
        <div class="metadata">
        <h1 class="title">草枕</h1>
        <h2 class="author">夏目漱石</h2>
        </div>
        <div class="main_text">
        テスト<br />
        </div>
        </body>
        </html>
        """

        let work = try AozoraParser.parse(html: html, sourceURL: "test://5")

        XCTAssertEqual(work.title, "草枕")
        XCTAssertEqual(work.author, "夏目漱石")
        XCTAssertEqual(work.aozoraURL, "test://5")
    }

    // MARK: - Headings

    func testParsesHeadings() throws {
        let html = wrapInAozoraHTML("""
        <div class="main_text">
        <h4 class="naka-midashi"><a class="midashi_anchor" id="midashi10">一</a></h4>
        本文テスト<br />
        </div>
        """)

        let work = try AozoraParser.parse(html: html, sourceURL: "test://6")

        let headingLine = work.lines.first { $0.isHeading }
        XCTAssertNotNil(headingLine)
        XCTAssertEqual(headingLine?.text, "一")
    }

    // MARK: - Line Breaks

    func testSplitsOnLineBreaks() throws {
        let html = wrapInAozoraHTML("""
        <div class="main_text">
        一行目<br />
        二行目<br />
        三行目<br />
        </div>
        """)

        let work = try AozoraParser.parse(html: html, sourceURL: "test://7")

        let texts = work.lines.map(\.text).filter { !$0.isEmpty }
        XCTAssertEqual(texts.count, 3)
        XCTAssertEqual(texts[0], "一行目")
        XCTAssertEqual(texts[1], "二行目")
        XCTAssertEqual(texts[2], "三行目")
    }

    // MARK: - Emphasis Preservation

    func testPreservesEmphasisText() throws {
        let html = wrapInAozoraHTML("""
        <div class="main_text">
        これは<em class="sesame_dot">強調</em>テストです<br />
        </div>
        """)

        let work = try AozoraParser.parse(html: html, sourceURL: "test://8")

        let line = work.lines[0]
        XCTAssertEqual(line.text, "これは強調テストです")
    }

    // MARK: - Helper

    private func wrapInAozoraHTML(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="ja">
        <head>
        <meta name="DC.Title" content="テスト" />
        <meta name="DC.Creator" content="テスト著者" />
        <title>テスト著者 テスト</title>
        </head>
        <body>
        <div class="metadata">
        <h1 class="title">テスト</h1>
        <h2 class="author">テスト著者</h2>
        </div>
        \(body)
        </body>
        </html>
        """
    }
}

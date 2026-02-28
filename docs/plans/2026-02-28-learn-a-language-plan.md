# Learn-a-Language Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an immersive Japanese reading tool that passively teaches vocabulary through contextual re-exposure across Aozora Bunko literary works.

**Architecture:** Two decoupled components — a Swift CLI preprocessing pipeline that tokenizes/annotates texts and writes to Supabase, and a Next.js reader that renders texts with hover tooltips. Pipeline runs offline; reader queries only pre-computed data.

**Tech Stack:** Swift 5.9+ (SPM), MeCab + UniDic (C interop), Next.js 14+ (React), Supabase (PostgreSQL), JMdict (XML), LLM API (Claude)

---

## Phase 1: Project Setup & Supabase Schema

### Task 1: Clone Aozora Bunko

**Files:**
- Create: `references/` directory

**Step 1: Clone the repository**

Run:
```bash
mkdir -p references
git clone --depth 1 https://github.com/aozorabunko/aozorabunko references/aozorabunko
```

**Step 2: Verify clone**

Run: `ls references/aozorabunko/cards/ | head -5`
Expected: Numbered directories (each is an author)

**Step 3: Add to .gitignore**

Add `references/aozorabunko` to `.gitignore` (it's 4GB+, don't track it).

**Step 4: Commit**

```bash
echo "references/aozorabunko" >> .gitignore
git add .gitignore
git commit -m "chore: add aozorabunko to gitignore"
```

---

### Task 2: Create Supabase Project & Schema

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`

**Step 1: Create Supabase project**

Go to https://supabase.com/dashboard and create a new project named `learn-a-language`. Save the project URL and anon key.

**Step 2: Create `.env.local` for credentials**

Create `.env.local` (already in .gitignore by default for Next.js):
```
NEXT_PUBLIC_SUPABASE_URL=https://xxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=xxxxx
```

**Step 3: Write the migration SQL**

Create `supabase/migrations/001_initial_schema.sql`:

```sql
-- Works table: one row per Aozora Bunko text
create table works (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  author text not null,
  aozora_id text unique not null,
  publish_year int,
  genre text,
  processed_at timestamptz default now()
);

-- Word entries: one row per unique base_form
create table word_entries (
  id uuid primary key default gen_random_uuid(),
  base_form text not null,
  pos text not null,
  reading text,
  jmdict_def text,
  ai_explanation text,
  cross_text_examples jsonb default '[]'::jsonb,
  unique(base_form, pos)
);

-- Tokens: every token in every work, in order
create table tokens (
  id uuid primary key default gen_random_uuid(),
  work_id uuid not null references works(id) on delete cascade,
  position int not null,
  surface text not null,
  base_form text not null,
  reading text,
  pos text not null,
  sentence_text text,
  word_entry_id uuid references word_entries(id)
);

create index idx_tokens_work_position on tokens(work_id, position);
create index idx_tokens_base_form on tokens(base_form);

-- User vocabulary: tracks which words the user has looked up
create table user_vocabulary (
  id uuid primary key default gen_random_uuid(),
  word_entry_id uuid not null references word_entries(id) on delete cascade,
  first_seen_at timestamptz default now(),
  exposure_count int default 1,
  last_seen_at timestamptz default now(),
  status text default 'new' check (status in ('new', 'learning', 'known')),
  unique(word_entry_id)
);

-- Enable Row Level Security (open for single user, no auth)
alter table works enable row level security;
alter table word_entries enable row level security;
alter table tokens enable row level security;
alter table user_vocabulary enable row level security;

create policy "public read works" on works for select using (true);
create policy "public read word_entries" on word_entries for select using (true);
create policy "public read tokens" on tokens for select using (true);
create policy "public all user_vocabulary" on user_vocabulary
  for all using (true) with check (true);
```

**Step 4: Apply migration via Supabase SQL editor**

Copy the SQL into Supabase Dashboard > SQL Editor > Run.

**Step 5: Commit**

```bash
mkdir -p supabase/migrations
git add supabase/migrations/001_initial_schema.sql
git commit -m "feat: add initial Supabase schema for works, tokens, word_entries, user_vocabulary"
```

---

### Task 3: Set Up Swift Preprocessing Package

**Files:**
- Create: `preprocessing/Package.swift`
- Create: `preprocessing/Sources/PipelineCLI/PipelineCLI.swift`
- Create: `preprocessing/Sources/Pipeline/Models.swift`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Preprocessing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "pipeline", targets: ["PipelineCLI"]),
        .library(name: "Pipeline", targets: ["Pipeline"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "PipelineCLI",
            dependencies: [
                "Pipeline",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "Pipeline",
            dependencies: []
        ),
        .testTarget(
            name: "PipelineTests",
            dependencies: ["Pipeline"]
        ),
    ]
)
```

**Step 2: Create CLI entry point**

Create `preprocessing/Sources/PipelineCLI/PipelineCLI.swift`:

```swift
import ArgumentParser
import Pipeline

@main
struct PipelineCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pipeline",
        abstract: "Preprocess Aozora Bunko texts for Learn-a-Language",
        subcommands: [Process.self]
    )
}

struct Process: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Process a single Aozora Bunko work"
    )

    @Argument(help: "Path to the Aozora Bunko HTML file")
    var inputPath: String

    func run() throws {
        print("Processing: \(inputPath)")
        // Pipeline steps will be added in subsequent tasks
    }
}
```

**Step 3: Create shared models**

Create `preprocessing/Sources/Pipeline/Models.swift`:

```swift
import Foundation

public struct WorkMetadata: Sendable {
    public let title: String
    public let author: String
    public let aozoraId: String
    public let publishYear: Int?

    public init(title: String, author: String, aozoraId: String, publishYear: Int? = nil) {
        self.title = title
        self.author = author
        self.aozoraId = aozoraId
        self.publishYear = publishYear
    }
}

public struct Token: Sendable {
    public let surface: String
    public let baseForm: String
    public let reading: String
    public let pos: String
    public let sentenceText: String

    public init(surface: String, baseForm: String, reading: String, pos: String, sentenceText: String) {
        self.surface = surface
        self.baseForm = baseForm
        self.reading = reading
        self.pos = pos
        self.sentenceText = sentenceText
    }
}

public struct WordEntry: Sendable {
    public let baseForm: String
    public let pos: String
    public let reading: String
    public let jmdictDef: String?
    public let aiExplanation: String?
    public var crossTextExamples: [CrossTextExample]

    public init(baseForm: String, pos: String, reading: String, jmdictDef: String? = nil, aiExplanation: String? = nil, crossTextExamples: [CrossTextExample] = []) {
        self.baseForm = baseForm
        self.pos = pos
        self.reading = reading
        self.jmdictDef = jmdictDef
        self.aiExplanation = aiExplanation
        self.crossTextExamples = crossTextExamples
    }
}

public struct CrossTextExample: Codable, Sendable {
    public let work: String
    public let author: String
    public let sentence: String

    public init(work: String, author: String, sentence: String) {
        self.work = work
        self.author = author
        self.sentence = sentence
    }
}
```

**Step 4: Verify build**

Run: `cd preprocessing && swift build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add preprocessing/
git commit -m "feat: scaffold Swift preprocessing pipeline with models and CLI"
```

---

### Task 4: Set Up Next.js Reader

**Files:**
- Create: `reader/` (via create-next-app)
- Modify: `reader/package.json` (add supabase deps)

**Step 1: Create Next.js project**

```bash
npx create-next-app@latest reader --typescript --tailwind --eslint --app --src-dir --no-import-alias
```

**Step 2: Install Supabase client**

```bash
cd reader && npm install @supabase/supabase-js
```

**Step 3: Create Supabase client utility**

Create `reader/src/lib/supabase.ts`:

```typescript
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
```

**Step 4: Create TypeScript types matching Supabase schema**

Create `reader/src/lib/types.ts`:

```typescript
export interface Work {
  id: string;
  title: string;
  author: string;
  aozora_id: string;
  publish_year: number | null;
  genre: string | null;
  processed_at: string;
}

export interface TokenRecord {
  id: string;
  work_id: string;
  position: number;
  surface: string;
  base_form: string;
  reading: string | null;
  pos: string;
  sentence_text: string | null;
  word_entry_id: string | null;
}

export interface WordEntry {
  id: string;
  base_form: string;
  pos: string;
  reading: string | null;
  jmdict_def: string | null;
  ai_explanation: string | null;
  cross_text_examples: CrossTextExample[];
}

export interface CrossTextExample {
  work: string;
  author: string;
  sentence: string;
}

export interface UserVocabulary {
  id: string;
  word_entry_id: string;
  first_seen_at: string;
  exposure_count: number;
  last_seen_at: string;
  status: "new" | "learning" | "known";
}
```

**Step 5: Move .env.local into reader/**

```bash
mv .env.local reader/.env.local
```

**Step 6: Verify dev server**

Run: `cd reader && npm run dev`
Expected: Next.js dev server starts at localhost:3000

**Step 7: Commit**

```bash
git add reader/
echo "reader/.env.local" >> .gitignore
git add .gitignore
git commit -m "feat: scaffold Next.js reader with Supabase client and type definitions"
```

---

## Phase 2: Aozora Bunko Parser (Swift)

### Task 5: AozoraParser — Parse HTML to Text + Furigana

**Files:**
- Create: `preprocessing/Sources/Pipeline/AozoraParser.swift`
- Create: `preprocessing/Tests/PipelineTests/AozoraParserTests.swift`

**Step 1: Write the failing test**

Create `preprocessing/Tests/PipelineTests/AozoraParserTests.swift`:

```swift
import Testing
@testable import Pipeline

@Suite("AozoraParser")
struct AozoraParserTests {
    @Test("extracts plain text from HTML")
    func extractsPlainText() throws {
        let html = """
        <div class="main_text">
        <h1 class="title">走れメロス</h1>
        <h2 class="author">太宰治</h2>
        <br>
        メロスは激怒した。
        </div>
        """
        let result = try AozoraParser.parse(html: html)
        #expect(result.metadata.title == "走れメロス")
        #expect(result.metadata.author == "太宰治")
        #expect(result.text.contains("メロスは激怒した。"))
    }

    @Test("extracts furigana from ruby tags")
    func extractsFurigana() throws {
        let html = """
        <div class="main_text">
        <h1 class="title">テスト</h1>
        <h2 class="author">著者</h2>
        <br>
        <ruby><rb>激怒</rb><rp>（</rp><rt>げきど</rt><rp>）</rp></ruby>した。
        </div>
        """
        let result = try AozoraParser.parse(html: html)
        #expect(result.furigana["激怒"] == "げきど")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd preprocessing && swift test --filter AozoraParser`
Expected: FAIL — `AozoraParser` not found

**Step 3: Implement AozoraParser**

Create `preprocessing/Sources/Pipeline/AozoraParser.swift`:

```swift
import Foundation

public struct ParsedText: Sendable {
    public let metadata: WorkMetadata
    public let text: String
    public let furigana: [String: String]
}

public enum AozoraParser {
    public static func parse(html: String) throws -> ParsedText {
        let title = extractTag(html, className: "title") ?? "Unknown"
        let author = extractTag(html, className: "author") ?? "Unknown"

        let furigana = extractFurigana(html)
        let text = stripHTML(extractMainText(html))

        let metadata = WorkMetadata(
            title: title,
            author: author,
            aozoraId: ""
        )

        return ParsedText(metadata: metadata, text: text, furigana: furigana)
    }

    public static func parseFile(at path: String) throws -> ParsedText {
        let html = try String(contentsOfFile: path, encoding: .shiftJIS)
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        var result = try parse(html: html)
        return ParsedText(
            metadata: WorkMetadata(
                title: result.metadata.title,
                author: result.metadata.author,
                aozoraId: filename,
                publishYear: result.metadata.publishYear
            ),
            text: result.text,
            furigana: result.furigana
        )
    }

    private static func extractTag(_ html: String, className: String) -> String? {
        let pattern = "<[^>]+class=\"\(className)\"[^>]*>([^<]+)</[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)
              ),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractMainText(_ html: String) -> String {
        let pattern = "<div[^>]+class=\"main_text\"[^>]*>([\\s\\S]*?)</div>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: html, range: NSRange(html.startIndex..., in: html)
              ),
              let range = Range(match.range(at: 1), in: html) else {
            return html
        }
        return String(html[range])
    }

    private static func extractFurigana(_ html: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = "<ruby><rb>([^<]+)</rb><rp>[^<]*</rp><rt>([^<]+)</rt><rp>[^<]*</rp></ruby>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            if let kanjiRange = Range(match.range(at: 1), in: html),
               let readingRange = Range(match.range(at: 2), in: html) {
                result[String(html[kanjiRange])] = String(html[readingRange])
            }
        }
        return result
    }

    private static func stripHTML(_ html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd preprocessing && swift test --filter AozoraParser`
Expected: PASS

**Step 5: Commit**

```bash
git add preprocessing/Sources/Pipeline/AozoraParser.swift
git add preprocessing/Tests/PipelineTests/AozoraParserTests.swift
git commit -m "feat: add AozoraParser for HTML parsing and furigana extraction"
```

---

## Phase 3: MeCab Integration (C Interop)

### Task 6: Install MeCab + UniDic and Create C Bridge

**Files:**
- Create: `preprocessing/Sources/CMeCab/include/mecab_bridge.h`
- Create: `preprocessing/Sources/CMeCab/mecab_bridge.c`
- Modify: `preprocessing/Package.swift` (add CMeCab target)

**Step 1: Install MeCab and UniDic**

```bash
brew install mecab
# Install UniDic dictionary
pip3 install unidic
python3 -m unidic download
```

Verify: `echo "走れメロス" | mecab`
Expected: tokenized output with readings and POS tags

**Step 2: Create C bridge header**

Create `preprocessing/Sources/CMeCab/include/mecab_bridge.h`:

```c
#ifndef MECAB_BRIDGE_H
#define MECAB_BRIDGE_H

#include <mecab.h>

// Re-export mecab types and functions for Swift
// The header simply includes mecab.h to make it available

#endif
```

Create `preprocessing/Sources/CMeCab/module.modulemap`:

```
module CMeCab {
    header "include/mecab_bridge.h"
    link "mecab"
    export *
}
```

**Step 3: Update Package.swift to include CMeCab**

Add to targets array:

```swift
.systemLibrary(
    name: "CMeCab",
    pkgConfig: nil,
    providers: [.brew(["mecab"])]
),
```

Update Pipeline target dependencies:

```swift
.target(
    name: "Pipeline",
    dependencies: ["CMeCab"]
),
```

**Step 4: Verify build with MeCab linked**

Run: `cd preprocessing && swift build`
Expected: Build succeeds (may need to set `PKG_CONFIG_PATH` or linker flags for MeCab)

If linker errors, add to Package.swift Pipeline target:
```swift
linkerSettings: [
    .unsafeFlags(["-L/opt/homebrew/lib"]),
]
```

And to CMeCab:
```swift
.systemLibrary(
    name: "CMeCab",
    path: "Sources/CMeCab",
    pkgConfig: nil,
    providers: [.brew(["mecab"])]
),
```

**Step 5: Commit**

```bash
git add preprocessing/Sources/CMeCab/ preprocessing/Package.swift
git commit -m "feat: add CMeCab C bridge for MeCab tokenizer integration"
```

---

### Task 7: MeCabBridge — Swift Wrapper for Tokenization

**Files:**
- Create: `preprocessing/Sources/Pipeline/MeCabBridge.swift`
- Create: `preprocessing/Tests/PipelineTests/MeCabBridgeTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import Pipeline

@Suite("MeCabBridge")
struct MeCabBridgeTests {
    @Test("tokenizes simple Japanese sentence")
    func tokenizesSimpleSentence() throws {
        let bridge = try MeCabBridge()
        let tokens = try bridge.tokenize("メロスは激怒した。")

        #expect(tokens.count > 0)
        // First meaningful token should be メロス
        let merosu = tokens.first { $0.surface == "メロス" }
        #expect(merosu != nil)
        #expect(merosu?.pos.hasPrefix("名詞") == true)
    }

    @Test("returns base form for conjugated verbs")
    func returnsBaseForm() throws {
        let bridge = try MeCabBridge()
        let tokens = try bridge.tokenize("走った")

        let hashitta = tokens.first { $0.surface == "走っ" }
        #expect(hashitta?.baseForm == "走る")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd preprocessing && swift test --filter MeCabBridge`
Expected: FAIL — `MeCabBridge` not found

**Step 3: Implement MeCabBridge**

Create `preprocessing/Sources/Pipeline/MeCabBridge.swift`:

```swift
import Foundation
import CMeCab

public final class MeCabBridge: Sendable {
    private let mecab: OpaquePointer

    public init() throws {
        guard let m = mecab_new2("") else {
            let error = String(cString: mecab_strerror(nil))
            throw MeCabError.initFailed(error)
        }
        self.mecab = m
    }

    deinit {
        mecab_destroy(mecab)
    }

    public func tokenize(_ text: String) throws -> [MeCabToken] {
        guard let result = mecab_sparse_tostr(mecab, text) else {
            let error = String(cString: mecab_strerror(mecab))
            throw MeCabError.parseFailed(error)
        }

        let output = String(cString: result)
        return parseOutput(output)
    }

    public func tokenizeBySentence(_ text: String) throws -> [[MeCabToken]] {
        let sentences = splitSentences(text)
        return try sentences.map { sentence in
            try tokenize(sentence).map { token in
                MeCabToken(
                    surface: token.surface,
                    baseForm: token.baseForm,
                    reading: token.reading,
                    pos: token.pos,
                    sentenceText: sentence
                )
            }
        }
    }

    private func parseOutput(_ output: String) -> [MeCabToken] {
        var tokens: [MeCabToken] = []
        for line in output.split(separator: "\n") {
            let str = String(line)
            if str == "EOS" || str.isEmpty { continue }
            guard let token = parseLine(str) else { continue }
            tokens.append(token)
        }
        return tokens
    }

    private func parseLine(_ line: String) -> MeCabToken? {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let surface = String(parts[0])
        let features = parts[1].split(separator: ",").map(String.init)

        // UniDic format: pos1,pos2,pos3,pos4,conjType,conjForm,
        //                lForm,lemma,orth,pron,orthBase,pronBase,...
        let pos = features.first ?? "未知"
        let baseForm = features.count > 7 ? features[7] : surface
        let reading = features.count > 9 ? features[9] : ""

        return MeCabToken(
            surface: surface,
            baseForm: baseForm,
            reading: reading,
            pos: pos,
            sentenceText: ""
        )
    }

    private func splitSentences(_ text: String) -> [String] {
        let delimiters = CharacterSet(charactersIn: "。！？\n")
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if String(char).unicodeScalars.allSatisfy({ delimiters.contains($0) }) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { sentences.append(trimmed) }
        return sentences
    }
}

public struct MeCabToken: Sendable {
    public let surface: String
    public let baseForm: String
    public let reading: String
    public let pos: String
    public let sentenceText: String
}

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
```

**Step 4: Run test to verify it passes**

Run: `cd preprocessing && swift test --filter MeCabBridge`
Expected: PASS (requires MeCab installed on system)

**Step 5: Commit**

```bash
git add preprocessing/Sources/Pipeline/MeCabBridge.swift
git add preprocessing/Tests/PipelineTests/MeCabBridgeTests.swift
git commit -m "feat: add MeCabBridge Swift wrapper for Japanese tokenization"
```

---

## Phase 4: JMdict Dictionary Matching

### Task 8: Download and Parse JMdict

**Files:**
- Create: `preprocessing/Sources/Pipeline/JMDictMatcher.swift`
- Create: `preprocessing/Tests/PipelineTests/JMDictMatcherTests.swift`

**Step 1: Download JMdict**

```bash
mkdir -p references/jmdict
curl -L "https://www.edrdg.org/pub/Nihongo/JMdict_e.gz" -o references/jmdict/JMdict_e.gz
gunzip references/jmdict/JMdict_e.gz
```

Add to `.gitignore`: `references/jmdict`

**Step 2: Write the failing test**

```swift
import Testing
@testable import Pipeline

@Suite("JMDictMatcher")
struct JMDictMatcherTests {
    @Test("looks up a common noun")
    func looksUpNoun() throws {
        // Use a small test fixture instead of full JMdict
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <JMdict>
        <entry>
        <ent_seq>1000220</ent_seq>
        <k_ele><keb>明日</keb></k_ele>
        <r_ele><reb>あした</reb></r_ele>
        <sense>
        <pos>&n;</pos>
        <gloss>tomorrow</gloss>
        </sense>
        </entry>
        </JMdict>
        """
        let matcher = try JMDictMatcher(xmlString: xml)
        let result = matcher.lookup(baseForm: "明日")
        #expect(result?.gloss == "tomorrow")
    }

    @Test("returns nil for unknown word")
    func returnsNilForUnknown() throws {
        let matcher = try JMDictMatcher(xmlString: "<JMdict></JMdict>")
        let result = matcher.lookup(baseForm: "存在しない")
        #expect(result == nil)
    }
}
```

**Step 3: Implement JMDictMatcher**

Create `preprocessing/Sources/Pipeline/JMDictMatcher.swift`:

```swift
import Foundation

public struct JMDictEntry: Sendable {
    public let kanji: String
    public let reading: String
    public let pos: String
    public let gloss: String
}

public final class JMDictMatcher: @unchecked Sendable {
    private var entries: [String: JMDictEntry] = [:]

    public init(filePath: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        try parseXML(data: data)
    }

    public init(xmlString: String) throws {
        // Replace entity references for testing
        let cleaned = xmlString
            .replacingOccurrences(of: "&n;", with: "noun")
            .replacingOccurrences(of: "&v1;", with: "verb-ichidan")
            .replacingOccurrences(of: "&adj-i;", with: "adjective-i")
        guard let data = cleaned.data(using: .utf8) else {
            throw JMDictError.invalidData
        }
        try parseXML(data: data)
    }

    public func lookup(baseForm: String) -> JMDictEntry? {
        entries[baseForm]
    }

    private func parseXML(data: Data) throws {
        let parser = JMDictXMLParser(data: data)
        entries = parser.parse()
    }
}

private class JMDictXMLParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var entries: [String: JMDictEntry] = [:]

    private var currentElement = ""
    private var currentKanji = ""
    private var currentReading = ""
    private var currentPos = ""
    private var currentGloss = ""
    private var inEntry = false

    init(data: Data) {
        self.parser = XMLParser(data: data)
        super.init()
        self.parser.delegate = self
    }

    func parse() -> [String: JMDictEntry] {
        parser.parse()
        return entries
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        currentElement = elementName
        if elementName == "entry" {
            inEntry = true
            currentKanji = ""
            currentReading = ""
            currentPos = ""
            currentGloss = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry else { return }
        switch currentElement {
        case "keb": currentKanji += string
        case "reb": if currentReading.isEmpty { currentReading += string }
        case "pos": if currentPos.isEmpty { currentPos += string }
        case "gloss": if currentGloss.isEmpty { currentGloss += string }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "entry" {
            inEntry = false
            let key = currentKanji.isEmpty ? currentReading : currentKanji
            if !key.isEmpty {
                entries[key] = JMDictEntry(
                    kanji: currentKanji,
                    reading: currentReading,
                    pos: currentPos,
                    gloss: currentGloss
                )
            }
        }
        currentElement = ""
    }
}

public enum JMDictError: Error {
    case invalidData
    case fileNotFound
}
```

**Step 4: Run tests**

Run: `cd preprocessing && swift test --filter JMDictMatcher`
Expected: PASS

**Step 5: Commit**

```bash
git add preprocessing/Sources/Pipeline/JMDictMatcher.swift
git add preprocessing/Tests/PipelineTests/JMDictMatcherTests.swift
echo "references/jmdict" >> .gitignore
git add .gitignore
git commit -m "feat: add JMDictMatcher for dictionary lookups"
```

---

## Phase 5: AI Correction & Explanation

### Task 9: AICorrector — Fix Low-Confidence Tokens

**Files:**
- Create: `preprocessing/Sources/Pipeline/AICorrector.swift`
- Create: `preprocessing/Tests/PipelineTests/AICorrectorTests.swift`

This task uses the Anthropic API to correct MeCab tokenization errors
on literary/archaic Japanese. Design a protocol so it can be mocked in tests.

**Step 1: Write the failing test with a mock**

```swift
import Testing
@testable import Pipeline

struct MockLLMClient: LLMClient {
    func complete(prompt: String) async throws -> String {
        // Return a fixed correction response
        return """
        [{"surface":"切なく","baseForm":"切ない","reading":"せつなく","pos":"形容詞"}]
        """
    }
}

@Suite("AICorrector")
struct AICorrectorTests {
    @Test("corrects tokens via LLM")
    func correctsTokens() async throws {
        let corrector = AICorrector(client: MockLLMClient())
        let badToken = MeCabToken(
            surface: "切なく",
            baseForm: "切なく",  // MeCab failed to find base form
            reading: "",
            pos: "未知",
            sentenceText: "それが切なく美しかった"
        )
        let corrected = try await corrector.correct(tokens: [badToken])
        #expect(corrected[0].baseForm == "切ない")
        #expect(corrected[0].pos == "形容詞")
    }
}
```

**Step 2: Implement AICorrector with protocol**

Create `preprocessing/Sources/Pipeline/AICorrector.swift`:

```swift
import Foundation

public protocol LLMClient: Sendable {
    func complete(prompt: String) async throws -> String
}

public struct AICorrector: Sendable {
    private let client: LLMClient

    public init(client: LLMClient) {
        self.client = client
    }

    public func correct(tokens: [MeCabToken]) async throws -> [MeCabToken] {
        guard !tokens.isEmpty else { return [] }

        let prompt = buildCorrectionPrompt(tokens: tokens)
        let response = try await client.complete(prompt: prompt)
        return try parseCorrectionResponse(response, original: tokens)
    }

    private func buildCorrectionPrompt(tokens: [MeCabToken]) -> String {
        let tokenList = tokens.map { token in
            "surface=\(token.surface), baseForm=\(token.baseForm), " +
            "pos=\(token.pos), context=\"\(token.sentenceText)\""
        }.joined(separator: "\n")

        return """
        以下の形態素解析結果に誤りがある可能性があります。
        文脈を考慮して、正しい原形（baseForm）、品詞（pos）、読み（reading）を返してください。
        JSON配列で返してください。

        \(tokenList)

        返答形式: [{"surface":"...","baseForm":"...","reading":"...","pos":"..."}]
        """
    }

    private func parseCorrectionResponse(
        _ response: String, original: [MeCabToken]
    ) throws -> [MeCabToken] {
        guard let data = response.data(using: .utf8),
              let items = try? JSONDecoder().decode([CorrectionItem].self, from: data) else {
            return original
        }
        return zip(original, items).map { orig, correction in
            MeCabToken(
                surface: correction.surface,
                baseForm: correction.baseForm,
                reading: correction.reading,
                pos: correction.pos,
                sentenceText: orig.sentenceText
            )
        }
    }
}

private struct CorrectionItem: Decodable {
    let surface: String
    let baseForm: String
    let reading: String
    let pos: String
}
```

**Step 3: Run tests**

Run: `cd preprocessing && swift test --filter AICorrector`
Expected: PASS

**Step 4: Commit**

```bash
git add preprocessing/Sources/Pipeline/AICorrector.swift
git add preprocessing/Tests/PipelineTests/AICorrectorTests.swift
git commit -m "feat: add AICorrector with LLMClient protocol for token correction"
```

---

### Task 10: AIExplainer — Generate Japanese Explanations for Verbs/Adjectives

**Files:**
- Create: `preprocessing/Sources/Pipeline/AIExplainer.swift`
- Create: `preprocessing/Tests/PipelineTests/AIExplainerTests.swift`

Same pattern as AICorrector: protocol-based LLM client, mockable.

**Step 1: Write the failing test**

```swift
import Testing
@testable import Pipeline

struct MockExplainerClient: LLMClient {
    func complete(prompt: String) async throws -> String {
        return """
        {"explanation":"胸が締め付けられるような、苦しくも切ない感情を表す形容詞。"}
        """
    }
}

@Suite("AIExplainer")
struct AIExplainerTests {
    @Test("generates Japanese explanation for adjective")
    func generatesExplanation() async throws {
        let explainer = AIExplainer(client: MockExplainerClient())
        let result = try await explainer.explain(
            baseForm: "切ない",
            pos: "形容詞",
            exampleSentences: ["切ない気持ちが胸に迫ってきた"]
        )
        #expect(result.contains("形容詞"))
    }
}
```

**Step 2: Implement AIExplainer**

Create `preprocessing/Sources/Pipeline/AIExplainer.swift`:

```swift
import Foundation

public struct AIExplainer: Sendable {
    private let client: LLMClient

    public init(client: LLMClient) {
        self.client = client
    }

    public func explain(
        baseForm: String,
        pos: String,
        exampleSentences: [String]
    ) async throws -> String {
        let examples = exampleSentences
            .prefix(5)
            .map { "・\($0)" }
            .joined(separator: "\n")

        let prompt = """
        以下の日本語の単語について、簡潔な日本語の説明を書いてください。
        学習者向けに、やさしい日本語で書いてください。

        単語: \(baseForm)
        品詞: \(pos)
        例文:
        \(examples)

        JSON形式で返してください: {"explanation":"..."}
        """

        let response = try await client.complete(prompt: prompt)
        guard let data = response.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(
                ExplanationResponse.self, from: data
              ) else {
            return ""
        }
        return parsed.explanation
    }
}

private struct ExplanationResponse: Decodable {
    let explanation: String
}
```

**Step 3: Run tests**

Run: `cd preprocessing && swift test --filter AIExplainer`
Expected: PASS

**Step 4: Commit**

```bash
git add preprocessing/Sources/Pipeline/AIExplainer.swift
git add preprocessing/Tests/PipelineTests/AIExplainerTests.swift
git commit -m "feat: add AIExplainer for generating Japanese word explanations"
```

---

## Phase 6: Supabase Writer & Pipeline Orchestration

### Task 11: SupabaseWriter

**Files:**
- Create: `preprocessing/Sources/Pipeline/SupabaseWriter.swift`

**Step 1: Add Supabase Swift dependency to Package.swift**

Add to dependencies:
```swift
.package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),
```

Add to Pipeline target dependencies:
```swift
.product(name: "Supabase", package: "supabase-swift"),
```

**Step 2: Implement SupabaseWriter**

```swift
import Foundation
import Supabase

public actor SupabaseWriter {
    private let client: SupabaseClient

    public init(url: String, key: String) {
        self.client = SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: key
        )
    }

    public func writeWork(_ metadata: WorkMetadata) async throws -> String {
        struct WorkInsert: Encodable {
            let title: String
            let author: String
            let aozora_id: String
            let publish_year: Int?
        }
        let insert = WorkInsert(
            title: metadata.title,
            author: metadata.author,
            aozora_id: metadata.aozoraId,
            publish_year: metadata.publishYear
        )
        struct WorkRow: Decodable { let id: String }
        let rows: [WorkRow] = try await client.from("works")
            .insert(insert)
            .select("id")
            .execute()
            .value
        return rows.first!.id
    }

    public func writeTokens(_ tokens: [Token], workId: String) async throws {
        struct TokenInsert: Encodable {
            let work_id: String
            let position: Int
            let surface: String
            let base_form: String
            let reading: String
            let pos: String
            let sentence_text: String
        }
        let inserts = tokens.enumerated().map { i, t in
            TokenInsert(
                work_id: workId,
                position: i,
                surface: t.surface,
                base_form: t.baseForm,
                reading: t.reading,
                pos: t.pos,
                sentence_text: t.sentenceText
            )
        }
        // Batch insert in chunks of 500
        for chunk in inserts.chunked(into: 500) {
            try await client.from("tokens").insert(chunk).execute()
        }
    }

    public func upsertWordEntry(_ entry: WordEntry) async throws {
        struct WordInsert: Encodable {
            let base_form: String
            let pos: String
            let reading: String
            let jmdict_def: String?
            let ai_explanation: String?
        }
        let insert = WordInsert(
            base_form: entry.baseForm,
            pos: entry.pos,
            reading: entry.reading,
            jmdict_def: entry.jmdictDef,
            ai_explanation: entry.aiExplanation
        )
        try await client.from("word_entries")
            .upsert(insert, onConflict: "base_form,pos")
            .execute()
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

**Step 3: Commit**

```bash
git add preprocessing/Sources/Pipeline/SupabaseWriter.swift preprocessing/Package.swift
git commit -m "feat: add SupabaseWriter for persisting preprocessed data"
```

---

### Task 12: Pipeline Orchestrator & CLI

**Files:**
- Modify: `preprocessing/Sources/PipelineCLI/PipelineCLI.swift`
- Create: `preprocessing/Sources/Pipeline/PipelineOrchestrator.swift`
- Create: `preprocessing/Sources/Pipeline/AnthropicClient.swift`

**Step 1: Create real LLM client**

Create `preprocessing/Sources/Pipeline/AnthropicClient.swift`:

```swift
import Foundation

public struct AnthropicClient: LLMClient {
    private let apiKey: String
    private let model: String

    public init(apiKey: String, model: String = "claude-sonnet-4-6") {
        self.apiKey = apiKey
        self.model = model
    }

    public func complete(prompt: String) async throws -> String {
        var request = URLRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!
        )
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        return response.content.first?.text ?? ""
    }
}

private struct AnthropicResponse: Decodable {
    let content: [ContentBlock]
    struct ContentBlock: Decodable {
        let text: String
    }
}
```

**Step 2: Create PipelineOrchestrator**

Create `preprocessing/Sources/Pipeline/PipelineOrchestrator.swift`:

```swift
import Foundation

public struct PipelineOrchestrator: Sendable {
    private let mecab: MeCabBridge
    private let jmdict: JMDictMatcher
    private let corrector: AICorrector
    private let explainer: AIExplainer
    private let writer: SupabaseWriter

    public init(
        mecab: MeCabBridge,
        jmdict: JMDictMatcher,
        corrector: AICorrector,
        explainer: AIExplainer,
        writer: SupabaseWriter
    ) {
        self.mecab = mecab
        self.jmdict = jmdict
        self.corrector = corrector
        self.explainer = explainer
        self.writer = writer
    }

    public func process(filePath: String) async throws {
        print("[1/6] Parsing Aozora Bunko HTML...")
        let parsed = try AozoraParser.parseFile(at: filePath)

        print("[2/6] Tokenizing with MeCab...")
        let sentenceTokens = try mecab.tokenizeBySentence(parsed.text)
        let allTokens = sentenceTokens.flatMap { $0 }

        print("[3/6] AI correction for uncertain tokens...")
        let uncertainTokens = allTokens.filter { $0.pos == "未知" || $0.baseForm == $0.surface }
        let correctedTokens: [MeCabToken]
        if !uncertainTokens.isEmpty {
            correctedTokens = try await corrector.correct(tokens: uncertainTokens)
        } else {
            correctedTokens = []
        }

        // Merge corrections back
        var finalTokens = allTokens
        var correctionMap: [String: MeCabToken] = [:]
        for token in correctedTokens {
            correctionMap[token.surface] = token
        }
        finalTokens = finalTokens.map { token in
            correctionMap[token.surface] ?? token
        }

        print("[4/6] Matching with JMdict...")
        var wordEntries: [String: WordEntry] = [:]
        for token in finalTokens {
            let key = token.baseForm
            if wordEntries[key] != nil { continue }

            let jmdef = jmdict.lookup(baseForm: token.baseForm)
            wordEntries[key] = WordEntry(
                baseForm: token.baseForm,
                pos: token.pos,
                reading: token.reading,
                jmdictDef: jmdef?.gloss
            )
        }

        print("[5/6] AI explanations for verbs/adjectives...")
        let verbAdj = wordEntries.values.filter {
            $0.pos.hasPrefix("動詞") || $0.pos.hasPrefix("形容詞")
        }
        for entry in verbAdj {
            let sentences = finalTokens
                .filter { $0.baseForm == entry.baseForm }
                .map(\.sentenceText)
                .uniqued()
                .prefix(5)
            let explanation = try await explainer.explain(
                baseForm: entry.baseForm,
                pos: entry.pos,
                exampleSentences: Array(sentences)
            )
            wordEntries[entry.baseForm] = WordEntry(
                baseForm: entry.baseForm,
                pos: entry.pos,
                reading: entry.reading,
                jmdictDef: entry.jmdictDef,
                aiExplanation: explanation
            )
        }

        print("[6/6] Writing to Supabase...")
        let workId = try await writer.writeWork(parsed.metadata)
        let tokens = finalTokens.map { t in
            Token(
                surface: t.surface,
                baseForm: t.baseForm,
                reading: t.reading,
                pos: t.pos,
                sentenceText: t.sentenceText
            )
        }
        try await writer.writeTokens(tokens, workId: workId)
        for entry in wordEntries.values {
            try await writer.upsertWordEntry(entry)
        }

        print("Done! Processed \(finalTokens.count) tokens, " +
              "\(wordEntries.count) unique words.")
    }
}

extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
```

**Step 3: Update CLI to wire everything together**

Update `preprocessing/Sources/PipelineCLI/PipelineCLI.swift` — the Process
command should read environment variables for API keys and Supabase config,
instantiate all components, and call the orchestrator.

**Step 4: Commit**

```bash
git add preprocessing/Sources/
git commit -m "feat: add pipeline orchestrator and Anthropic client"
```

---

## Phase 7: Next.js Reader Frontend

### Task 13: Article List Page

**Files:**
- Modify: `reader/src/app/page.tsx`

**Step 1: Create the article list page**

Replace `reader/src/app/page.tsx` with a server component that fetches
works from Supabase and renders a simple list with title + author.
Each item links to `/works/[id]`.

**Step 2: Verify**

Run: `cd reader && npm run dev`
Navigate to localhost:3000, should see list of works (empty until pipeline runs).

**Step 3: Commit**

```bash
git add reader/src/app/page.tsx
git commit -m "feat: add article list page"
```

---

### Task 14: Article Reading Page (Core)

**Files:**
- Create: `reader/src/app/works/[id]/page.tsx`
- Create: `reader/src/components/TokenSpan.tsx`
- Create: `reader/src/components/Tooltip.tsx`
- Create: `reader/src/hooks/useUserVocabulary.ts`

This is the most complex frontend task. It renders the tokenized text
and handles the hover/click interactions.

**Step 1: Create the reading page**

`reader/src/app/works/[id]/page.tsx` — Server component that:
1. Fetches work metadata from `works` table
2. Fetches all tokens for this work, ordered by position
3. Fetches word_entries for all unique base_forms in this work
4. Passes data to a client component for interactive rendering

**Step 2: Create TokenSpan component**

`reader/src/components/TokenSpan.tsx` — Client component for each token:
- Renders the surface text as a `<span>`
- If the word is in user_vocabulary → add underline CSS class
- On hover/click → show Tooltip
- Implements two-tier behavior:
  - Known word: `onMouseEnter` → instant show
  - New word: `onClick` or 500ms `onMouseEnter` delay

**Step 3: Create Tooltip component**

`reader/src/components/Tooltip.tsx` — Renders the tooltip popup:
- Positioned near the hovered token
- Content depends on POS (Constitution Principle II):
  - Noun: reading + JMdict definition + cross-text count
  - Verb/Adj: reading + cross-text examples + collapsible JMdict def
- Uses absolute positioning with a portal

**Step 4: Create useUserVocabulary hook**

`reader/src/hooks/useUserVocabulary.ts`:
- Fetches user's vocabulary from `user_vocabulary` table on mount
- Returns a Set of known word_entry_ids for instant lookup
- Provides `markAsLookedUp(wordEntryId)` function that:
  - Upserts into `user_vocabulary` (creates or increments exposure_count)
  - Updates local state

**Step 5: Verify end-to-end**

After pipeline has processed at least one work, navigate to
`localhost:3000/works/<id>` and verify:
- Text renders with all tokens
- Hovering shows tooltips
- Looking up a word adds it to vocabulary
- On refresh, that word now has instant hover

**Step 6: Commit**

```bash
git add reader/src/
git commit -m "feat: add article reading page with hover tooltips and vocabulary tracking"
```

---

### Task 15: Visual Indicators for Learning Words

**Files:**
- Modify: `reader/src/components/TokenSpan.tsx`
- Create: `reader/src/styles/tokens.css`

**Step 1: Add CSS classes for learning states**

```css
/* reader/src/styles/tokens.css */
.token {
  cursor: pointer;
  transition: border-bottom 0.2s;
}

.token--new:hover {
  border-bottom: 1px dashed #94a3b8;
}

.token--learning-1 {
  border-bottom: 1px solid #cbd5e1; /* exposure 1-2 */
}

.token--learning-2 {
  border-bottom: 2px solid #64748b; /* exposure 3-4 */
}

/* exposure 5+ → no underline (assumed learned) */
```

**Step 2: Update TokenSpan to apply classes based on exposure_count**

**Step 3: Commit**

```bash
git add reader/src/
git commit -m "feat: add visual indicators for vocabulary learning states"
```

---

## Phase 8: Cross-Text Index & Integration

### Task 16: CrossTextIndexer (Swift)

**Files:**
- Create: `preprocessing/Sources/Pipeline/CrossTextIndexer.swift`

After all works are processed, run this to:
1. Query all tokens grouped by base_form
2. For each word, collect up to 10 sentences from different works
3. Update `word_entries.cross_text_examples` as JSONB

Run via CLI: `swift run pipeline build-index`

**Step 1: Implement CrossTextIndexer**

```swift
public actor CrossTextIndexer {
    private let writer: SupabaseWriter

    public init(writer: SupabaseWriter) {
        self.writer = writer
    }

    public func buildIndex() async throws {
        // Query all word_entries
        // For each, find tokens with that base_form across all works
        // Collect unique sentences with work metadata
        // Update cross_text_examples
        print("Building cross-text index...")
        // Implementation uses Supabase queries
    }
}
```

**Step 2: Commit**

```bash
git add preprocessing/Sources/Pipeline/CrossTextIndexer.swift
git commit -m "feat: add CrossTextIndexer for building cross-text word usage index"
```

---

### Task 17: Process MVP Works

**Step 1: Find the 5 MVP work files in Aozora Bunko**

```bash
# 走れメロス by 太宰治
find references/aozorabunko -path "*/太宰治/走れメロス*" -name "*.html" | head -1

# 注文の多い料理店 by 宮沢賢治
find references/aozorabunko -path "*/宮沢賢治/注文の多い料理店*" -name "*.html" | head -1

# Repeat for 羅生門, 坊っちゃん, 銀河鉄道の夜
```

**Step 2: Process each work**

```bash
cd preprocessing
swift run pipeline process <path-to-file>
# Repeat for each work
```

**Step 3: Build cross-text index**

```bash
swift run pipeline build-index
```

**Step 4: Verify in Supabase dashboard**

- `works` table should have 5 rows
- `tokens` table should have thousands of rows
- `word_entries` table should have hundreds of unique words
- `word_entries.cross_text_examples` should have data for common words

---

## Phase 9: Deploy

### Task 18: Deploy Reader to Vercel

**Step 1: Push to GitHub**

```bash
git push origin main
```

**Step 2: Connect to Vercel**

- Go to vercel.com, import the repository
- Set root directory to `reader/`
- Add environment variables:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`

**Step 3: Deploy and verify**

After deployment, verify all success criteria:

1. [ ] Can read a full article with hover explanations
2. [ ] Previously looked-up words auto-highlight and show instant tooltips
3. [ ] Verb/adjective tooltips show cross-text usage examples
4. [ ] Article load time < 2 seconds
5. [ ] Pipeline processed works in < 5 minutes each

---

## Task Dependency Graph

```
Task 1 (Clone Aozora) ─────────────────────────────────────┐
Task 2 (Supabase Schema) ──────────────────────────┐       │
Task 3 (Swift Package) ────┐                       │       │
Task 4 (Next.js Setup) ────┼───────────────────────┼───────┤
                            │                       │       │
Task 5 (AozoraParser) ◄────┘                       │       │
Task 6 (CMeCab Bridge) ◄───────────────────────────┤       │
Task 7 (MeCabBridge) ◄─── Task 6                   │       │
Task 8 (JMDict) ◄──────────────────────────────────┼───────┘
Task 9 (AICorrector) ◄─── Task 7                   │
Task 10 (AIExplainer) ◄── Task 9                   │
Task 11 (SupabaseWriter) ◄─────────────────────────┘
Task 12 (Orchestrator) ◄── Task 5,7,8,9,10,11
                            │
Task 13 (List Page) ◄────── Task 4,2
Task 14 (Reading Page) ◄── Task 13
Task 15 (Visual Indicators) ◄── Task 14
Task 16 (CrossTextIndexer) ◄── Task 11
                            │
Task 17 (Process Works) ◄── Task 12,16,1
Task 18 (Deploy) ◄──────── Task 15,17
```

## Parallel Opportunities

- Tasks 1, 2, 3, 4 can all run in parallel (setup phase)
- Tasks 5, 6, 8 can run in parallel (after Task 3)
- Tasks 13, 14, 15 can be built with mock data before pipeline is ready
- Task 8 (JMDict) is independent of MeCab work

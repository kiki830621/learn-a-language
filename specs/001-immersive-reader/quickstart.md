# Quickstart: Immersive Japanese Reader

**Date**: 2026-02-28
**Status**: Phase 1 Output

## Prerequisites

- macOS 14+ with Xcode 15+ (Swift 5.9+)
- Node.js 20+ with npm/pnpm
- Homebrew
- A Supabase project (free tier is sufficient)

## 1. Install System Dependencies

```bash
# MeCab tokenizer + UniDic dictionary
brew install mecab mecab-unidic

# Verify MeCab works
echo "走れメロス" | mecab
```

## 2. Download JMdict Data

```bash
mkdir -p preprocessing/data
cd preprocessing/data

# Download jmdict-simplified (English, full)
curl -L -o jmdict-eng.json.tgz \
  "https://github.com/scriptin/jmdict-simplified/releases/latest/download/jmdict-eng-3.6.1.json.tgz"
tar xzf jmdict-eng.json.tgz
rm jmdict-eng.json.tgz

cd ../..
```

## 3. Set Up Supabase

1. Create a project at [supabase.com](https://supabase.com)
2. Go to **SQL Editor** and run the migration from
   [`data-model.md`](specs/001-immersive-reader/data-model.md#sql-migration)
3. Go to **Settings > Database** and note the connection details

```bash
# Create .env file at repo root
cat > .env.local <<'EOF'
# Supabase (for Next.js reader)
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_REF.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key

# Postgres (for Swift pipeline)
PGHOST=db.YOUR_REF.supabase.co
PGPORT=5432
PGUSER=postgres
PGPASSWORD=your-db-password
PGDATABASE=postgres

# Claude API (for pipeline AI steps)
ANTHROPIC_API_KEY=your-api-key
EOF
```

## 4. Build the Swift Pipeline

```bash
cd preprocessing
swift build
```

If MeCab headers are not found, verify the Homebrew paths:
```bash
# Check MeCab installation
brew --prefix mecab
# Should be /opt/homebrew/opt/mecab (Apple Silicon)
# or /usr/local/opt/mecab (Intel)
```

## 5. Process a Test Work

```bash
# Load environment variables
source ../.env.local

# Process Rashomon (short, good for testing)
swift run pipeline process \
  "https://www.aozora.gr.jp/cards/000879/files/127_15260.html" \
  --verbose
```

## 6. Set Up the Next.js Reader

```bash
cd reader
npm install  # or pnpm install

# Development server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to see the work list.

## 7. Process All MVP Works and Build Index

```bash
cd preprocessing

# Process all 5 MVP works
swift run pipeline process "https://www.aozora.gr.jp/cards/000035/files/1567_14913.html"  # 走れメロス
swift run pipeline process "https://www.aozora.gr.jp/cards/000081/files/43754_17659.html"  # 注文の多い料理店
swift run pipeline process "https://www.aozora.gr.jp/cards/000879/files/127_15260.html"    # 羅生門
swift run pipeline process "https://www.aozora.gr.jp/cards/000148/files/752_14964.html"    # 坊っちゃん
swift run pipeline process "https://www.aozora.gr.jp/cards/000081/files/456_15050.html"    # 銀河鉄道の夜

# Build cross-text index
swift run pipeline index --verbose
```

## Verification

After processing, verify in the reader:

1. Work list shows all 5 works with token counts
2. Click any work to open the reading view
3. Hover over a word to see the tooltip (reading + definition/examples)
4. Look up a word, then navigate to another work — the word should be
   underlined and show an instant tooltip

## Project Structure

```
learn-a-language/
├── preprocessing/           # Swift CLI pipeline
│   ├── Package.swift
│   ├── Sources/
│   └── Tests/
├── reader/                  # Next.js web reader
│   ├── package.json
│   ├── src/
│   └── tests/
├── supabase/                # Database migrations
│   └── migrations/
├── specs/                   # Feature specifications
│   └── 001-immersive-reader/
└── .env.local               # Environment variables (gitignored)
```

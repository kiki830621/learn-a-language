# Learn a Language — Immersive Japanese Reader

An immersive reading tool for Japanese literature. Read classic works from Aozora Bunko with interactive vocabulary tooltips — all definitions in Japanese to maintain immersion.

**Live**: https://learn-a-language.vercel.app

## How It Works

1. Browse a curated library of Japanese literary works (currently 274 works by Dazai Osamu)
2. Click any word to see its reading, part of speech, and Japanese definition
3. Cross-text examples show the same word used in other works
4. Vocabulary tracking adapts highlights based on your familiarity

## Architecture

```
reader/          Next.js 16 frontend (React 19, Tailwind CSS 4, Supabase JS SDK)
preprocessing/   Swift CLI pipeline (MeCab tokenizer, JMdict matching, Claude AI)
db/              Supabase migrations (BCNF-normalized schema)
```

### Reader (`reader/`)

- **Next.js 16** with App Router and Server Components
- **Supabase** for data fetching (works, tokens, word entries, sentences)
- **Floating UI** for positioned word tooltips
- **Tailwind CSS 4** for styling

### Preprocessing Pipeline (`preprocessing/`)

Swift CLI that processes Aozora Bunko HTML files through 6 steps:

1. Parse HTML (Aozora format)
2. Tokenize with MeCab + UniDic
3. AI correction (Claude API — optional)
4. JMdict dictionary matching
5. AI explanation generation (Claude API — optional)
6. Write to Supabase (PostgresNIO)

```bash
# Process a single work
pipeline process <aozora-html-url> [--skip-ai] [--dry-run]

# Batch process a directory
pipeline batch <directory> [--skip-ai] [--limit 10]

# List processed works
pipeline list
```

### Database Schema

BCNF-normalized PostgreSQL on Supabase:

- `works` — literary works (title, author, source URL)
- `sentences` — text lines per work
- `tokens` — individual words with position, linked to sentences and word entries
- `word_entries` — unique vocabulary (base form, POS, reading, AI explanation)
- `cross_text_examples` — same word appearing across different works
- `user_vocab` — per-user vocabulary tracking (exposure count, status)

## Development

### Reader

```bash
cd reader
cp .env.local.example .env.local  # Add Supabase keys
npm install
npm run dev
```

### Preprocessing

Requires macOS with Homebrew:

```bash
brew install mecab mecab-unidic
cd preprocessing
swift build
```

Environment variables: `PGHOST`, `PGUSER`, `PGPASSWORD`, `PGPORT`, `PGDATABASE`, `ANTHROPIC_API_KEY` (optional), `JMDICT_PATH`.

## License

Private project.

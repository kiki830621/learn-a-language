# learn-a-language Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-02

## Active Technologies

- Swift 5.9+ (pipeline CLI), TypeScript / Next.js 14+ (reader) + MeCab + UniDic (C interop), JMdict (XML), Supabase JS SDK, Claude API (pipeline only) (001-immersive-reader)

## Project Structure

```text
preprocessing/          # Swift pipeline CLI (parse, tokenize, DB write)
  Sources/Pipeline/     # Core library (AozoraParser, MeCabBridge, SupabaseWriter, etc.)
  Sources/PipelineCLI/  # CLI commands (process, batch, list, index)
  Tests/
reader/                 # Next.js 14+ frontend (immersive reader)
db/migrations/          # SQL schema migrations (001-003)
specs/                  # Feature specifications
references/             # Cloned external repos (gitignored)
```

## Commands

```bash
# Pipeline CLI (run from preprocessing/)
swift build
swift run pipeline process <html-file> [--skip-ai] [--dry-run]
swift run pipeline batch <directory> [--skip-ai] [--limit N]
swift run pipeline list

# Reader (run from reader/)
npm test && npm run lint
```

## Environment Variables

Pipeline requires PG* vars for Supabase direct connection (see .env.local.example):
`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`

## Code Style

Swift 5.9+ (pipeline CLI), TypeScript / Next.js 14+ (reader): Follow standard conventions

## Recent Changes

- 001-immersive-reader: Added Swift 5.9+ (pipeline CLI), TypeScript / Next.js 14+ (reader) + MeCab + UniDic (C interop), JMdict (XML), Supabase JS SDK, Claude API (pipeline only)
- 001-immersive-reader: Pipeline DB writes implemented — SupabaseWriter connects via PostgresNIO+TLS, batch processes Aozora Bunko HTML files with sentence tracking and BCNF-compliant writes (works → sentences → word_entries → tokens). 274 太宰治 works (1.8M tokens) loaded.

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->

# CLI Interface Contract

**Date**: 2026-02-28
**Status**: Phase 1 Output
**Consumer**: Developer (local execution)

## Overview

The preprocessing pipeline is a Swift CLI tool that processes Aozora
Bunko HTML files and writes structured data to Supabase. It is run
locally on macOS.

## Command Structure

```
pipeline <command> [options]
```

### Commands

#### `process`

Process a single Aozora Bunko work end-to-end (Steps 1-6).

```
pipeline process <aozora-url> [options]
```

**Arguments**:
- `<aozora-url>`: URL or local path to an Aozora Bunko XHTML file

**Options**:
- `--dry-run`: Parse and tokenize without writing to Supabase
- `--skip-ai`: Skip AI correction and explanation steps (use MeCab output directly)
- `--verbose`: Print detailed progress for each pipeline step

**Example**:
```bash
pipeline process "https://www.aozora.gr.jp/cards/000035/files/1567_14913.html"
pipeline process ./data/rashomon.html --verbose
pipeline process ./data/rashomon.html --dry-run
```

**Output** (stdout):
```
[1/6] Parsing HTML...         ✓ 太宰治 — 走れメロス (892 lines)
[2/6] Tokenizing (MeCab)...   ✓ 8,432 tokens
[3/6] AI correction...        ✓ 127 tokens corrected (1.5%)
[4/6] JMdict matching...      ✓ 2,891 word entries matched
[5/6] AI explanation...        ✓ 412 explanations generated
[6/6] Writing to Supabase...  ✓ 1 work, 8432 tokens, 2891 word entries

Done in 3m 42s.
```

**Exit codes**:
- `0`: Success
- `1`: Input file not found or invalid
- `2`: MeCab initialization failed
- `3`: JMdict data not found
- `4`: Supabase connection failed
- `5`: AI API error (non-fatal if --skip-ai)

---

#### `index`

Build cross-text index for all processed works (Step 7).
Must run after all desired works are processed.

```
pipeline index [options]
```

**Options**:
- `--verbose`: Print detailed progress
- `--limit <n>`: Max cross-text examples per word entry (default: 5)

**Example**:
```bash
pipeline index
pipeline index --limit 3 --verbose
```

**Output** (stdout):
```
Building cross-text index...
  Scanning 5 works, 42,156 total tokens...
  Found 4,821 unique word entries
  Updated 1,234 entries with cross-text examples
  Average 2.7 examples per entry

Done in 45s.
```

**Exit codes**:
- `0`: Success
- `4`: Supabase connection failed

---

#### `list`

List all processed works in Supabase.

```
pipeline list
```

**Output** (stdout):
```
ID                                    Title              Author      Tokens  Processed
────────────────────────────────────  ─────────────────  ──────────  ──────  ──────────────────
a1b2c3d4-...                          走れメロス          太宰治        8,432  2026-02-28 14:30
e5f6g7h8-...                          羅生門              芥川龍之介    3,210  2026-02-28 14:35
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PGHOST` | Yes | Supabase Postgres host (`db.{ref}.supabase.co`) |
| `PGPORT` | No | Postgres port (default: `5432`) |
| `PGUSER` | Yes | Postgres username |
| `PGPASSWORD` | Yes | Postgres password |
| `PGDATABASE` | No | Database name (default: `postgres`) |
| `ANTHROPIC_API_KEY` | Yes* | Claude API key (*not required with --skip-ai) |
| `JMDICT_PATH` | No | Path to jmdict-eng JSON file (default: `./data/jmdict-eng.json`) |

## Data Files

The pipeline expects these data files to be available locally:

| File | Source | Size | Description |
|------|--------|------|-------------|
| `data/jmdict-eng.json` | [jmdict-simplified releases](https://github.com/scriptin/jmdict-simplified/releases) | ~38 MB | JMdict English dictionary |

## Prerequisites

| Dependency | Install Command | Notes |
|------------|----------------|-------|
| MeCab | `brew install mecab` | C library, required |
| UniDic | `brew install mecab-unidic` | Dictionary for MeCab |
| Swift 5.9+ | Xcode 15+ or swift.org toolchain | SPM build |
| PostgresNIO | (SPM dependency) | Auto-resolved by `swift build` |

## Pipeline Step Details

| Step | Input | Output | Can Fail? | Recovery |
|------|-------|--------|-----------|----------|
| 1. Parse HTML | XHTML file | Structured text + furigana | Yes | Fix input file |
| 2. Tokenize | Plain text | Token array | Yes | Check MeCab install |
| 3. AI Correct | Token array | Corrected tokens | Yes | --skip-ai to bypass |
| 4. JMdict Match | Token base_forms | Matched entries | No | Unmatched = no def |
| 5. AI Explain | Verbs/adjectives | Explanations | Yes | --skip-ai to bypass |
| 6. Write DB | All data | Supabase rows | Yes | Check credentials |
| 7. Cross-text Index | All works in DB | Updated examples | Yes | Re-run `index` |

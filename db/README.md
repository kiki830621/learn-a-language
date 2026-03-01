# Database — Immersive Japanese Reader

Supabase (PostgreSQL) schema and migrations for the immersive reader project.

## Quick Start

```bash
# 1. Set environment variables (from project root)
export $(cat .env.local | grep -v '^#' | grep -v '^$' | xargs)

# 2. Run migrations in order
psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -f db/migrations/001_initial_schema.sql
psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -f db/migrations/002_record_word_lookup.sql
psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -f db/migrations/003_normalize_bcnf.sql

# 3. Verify
psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -c "\dt"
```

## Schema Overview (BCNF)

```
works 1──* sentences
works 1──* tokens *──1 word_entries 1──1 user_vocabulary
                                    1──* cross_text_examples *──1 sentences
tokens *──1 sentences
```

| Table | Description |
|-------|-------------|
| `works` | Literary texts (title, author, Aozora URL) |
| `sentences` | Unique sentences per work (position, text) |
| `tokens` | Individual words in each work (surface, position, sentence_id FK) |
| `word_entries` | Shared vocabulary items (base_form + pos = identity key) |
| `cross_text_examples` | Usage examples linking word_entries to sentences across works |
| `user_vocabulary` | Per-word learning state (exposure count, status) |

## Migrations

| File | Description |
|------|-------------|
| `001_initial_schema.sql` | Core tables, indexes, RLS policies |
| `002_record_word_lookup.sql` | `record_word_lookup()` function (upsert + exposure tracking) |
| `003_normalize_bcnf.sql` | BCNF normalization: sentences table, cross_text_examples table |

Migrations are plain SQL, run sequentially. No migration framework required.

## Tables Detail

### works

Processed Aozora Bunko literary texts.

### sentences

Unique sentences per work, deduped by `(work_id, position)`.
Extracted from token sentence_text during BCNF normalization.

### tokens

Every word in a work, ordered by `position`. Links to:
- `word_entries` via `word_entry_id` (base_form, pos, reading available via JOIN)
- `sentences` via `sentence_id` (sentence text available via JOIN)
- `is_interactive = true` for content words (nouns, verbs, adjectives)
- `is_interactive = false` for punctuation, particles, whitespace

### word_entries

Unique vocabulary items keyed by `(base_form, pos)`. Contains:
- `jmdict_def` — dictionary definition (nouns)
- `ai_explanation` — AI-generated contextual explanation (verbs/adjectives)

### cross_text_examples

Usage examples linking word entries to sentences across different works.
Each row has `(word_entry_id, work_id, sentence_id, token_position)`.
Work title/author and sentence text are obtained via JOINs at query time.

### user_vocabulary

Learning state per word. Status transitions:

```
first lookup → [new] → second exposure → [learning] → exposure ≥ 5 or manual → [known]
                                                    ← manual reset ←
```

## RLS Policies

Single-user system with public access:
- All tables: `SELECT` allowed
- `user_vocabulary`: `INSERT` and `UPDATE` allowed
- `works`, `tokens`, `word_entries`: write via pipeline only (direct PG connection)

## Environment Variables

| Variable | Used By | Description |
|----------|---------|-------------|
| `PGHOST` | Pipeline (Swift) | `db.<ref>.supabase.co` |
| `PGPORT` | Pipeline (Swift) | Default `5432` |
| `PGUSER` | Pipeline (Swift) | Default `postgres` |
| `PGPASSWORD` | Pipeline (Swift) | Database password |
| `PGDATABASE` | Pipeline (Swift) | Default `postgres` |
| `NEXT_PUBLIC_SUPABASE_URL` | Reader (Next.js) | `https://<ref>.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Reader (Next.js) | Supabase anon (public) key |

# Data Model: Immersive Japanese Reader

**Date**: 2026-02-28
**Status**: Phase 1 Output
**Source**: [spec.md](spec.md) Key Entities + [design doc](../../docs/plans/2026-02-28-learn-a-language-design.md)

## Entity Relationship Diagram

```
works 1──* tokens *──1 word_entries 1──1 user_vocabulary
```

- A **work** contains many **tokens** (ordered by position)
- Many **tokens** share the same **word_entry** (via base_form + pos)
- A **word_entry** has at most one **user_vocabulary** record

## Entities

### works

Represents a literary text available for reading (FR-012).

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | |
| title | text | NOT NULL | Work title (e.g. 走れメロス) |
| author | text | NOT NULL | Author name (e.g. 太宰治) |
| aozora_url | text | NOT NULL, UNIQUE | Aozora Bunko file URL |
| publish_year | smallint | | Original publication year |
| token_count | int | NOT NULL, DEFAULT 0 | Total tokens in this work |
| processed_at | timestamptz | NOT NULL, DEFAULT now() | When preprocessing completed |

**Indexes**:
- `works_pkey` on `id`
- `works_aozora_url_key` on `aozora_url` (UNIQUE)

**Validation**:
- `title` and `author` must be non-empty strings
- `aozora_url` must be unique (prevent re-processing same file)
- `token_count` >= 0

### tokens

Represents an individual word/token in a work (FR-001). Every Japanese
word is individually addressable in the reader.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | |
| work_id | uuid | NOT NULL, FK -> works(id) ON DELETE CASCADE | Which work |
| position | int | NOT NULL | Sequential position in text (0-indexed) |
| surface | text | NOT NULL | Surface form as written in text |
| base_form | text | NOT NULL | Dictionary form (lemma) |
| reading | text | | Furigana reading (hiragana) |
| pos | text | NOT NULL | Part of speech tag |
| pos_detail | text | | Detailed POS (e.g. 固有名詞, 自立) |
| sentence_text | text | | Full sentence containing this token |
| is_interactive | boolean | NOT NULL, DEFAULT true | Whether tooltip is available |
| word_entry_id | uuid | FK -> word_entries(id) | Link to shared word entry |

**Indexes**:
- `tokens_pkey` on `id`
- `tokens_work_position` on `(work_id, position)` UNIQUE — ordered reading
- `tokens_word_entry_id` on `word_entry_id` — join to word_entries
- `tokens_base_form_pos` on `(base_form, pos)` — cross-text lookups

**Validation**:
- `(work_id, position)` is unique (no two tokens at same position in a work)
- `surface` must be non-empty
- `is_interactive` = false for punctuation, numbers, whitespace (no tooltip)
- `pos` must be a known MeCab POS tag

**POS tag values** (MeCab UniDic categories):
- `名詞` (noun), `動詞` (verb), `形容詞` (i-adjective),
  `形状詞` (na-adjective), `副詞` (adverb), `連体詞` (pre-noun),
  `接続詞` (conjunction), `感動詞` (interjection),
  `助詞` (particle), `助動詞` (auxiliary verb),
  `記号` (symbol), `補助記号` (supplementary symbol),
  `空白` (whitespace)

### word_entries

A unique vocabulary item identified by base_form + pos (FR-002, FR-003,
FR-004, FR-010). Shared across all works.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | |
| base_form | text | NOT NULL | Dictionary form (key) |
| pos | text | NOT NULL | Primary part of speech |
| reading | text | NOT NULL | Standard reading (hiragana) |
| jmdict_id | int | | JMdict entry sequence number |
| jmdict_def | text | | JMdict English definition |
| ai_explanation | text | | AI-generated contextual explanation |
| cross_text_examples | jsonb | NOT NULL, DEFAULT '[]' | Array of usage examples |
| work_count | int | NOT NULL, DEFAULT 0 | Number of works containing this word |

**Indexes**:
- `word_entries_pkey` on `id`
- `word_entries_base_form_pos` on `(base_form, pos)` UNIQUE — identity key

**Validation**:
- `(base_form, pos)` is unique (one entry per lemma + POS combination)
- `reading` must be non-empty hiragana/katakana
- `work_count` >= 0

**cross_text_examples JSONB structure**:
```json
[
  {
    "work_id": "uuid",
    "work_title": "走れメロス",
    "author": "太宰治",
    "sentence": "メロスは激怒した。",
    "token_position": 42
  }
]
```

**POS-dependent content** (FR-003, FR-004):
- Nouns (`名詞`): `jmdict_def` is primary content; `cross_text_examples` secondary
- Verbs (`動詞`), adjectives (`形容詞`, `形状詞`): `cross_text_examples`
  is primary; `jmdict_def` is secondary/collapsed

### user_vocabulary

The user's personal record of a word entry (FR-005, FR-006, FR-009,
FR-015). Single-user system — no user_id column needed.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | uuid | PK, DEFAULT gen_random_uuid() | |
| word_entry_id | uuid | NOT NULL, FK -> word_entries(id), UNIQUE | One record per word |
| first_seen_at | timestamptz | NOT NULL, DEFAULT now() | When first looked up |
| exposure_count | int | NOT NULL, DEFAULT 1 | Times exposed to this word |
| last_seen_at | timestamptz | NOT NULL, DEFAULT now() | Most recent exposure |
| status | text | NOT NULL, DEFAULT 'new' | Learning status |

**Indexes**:
- `user_vocabulary_pkey` on `id`
- `user_vocabulary_word_entry_id_key` on `word_entry_id` (UNIQUE)
- `user_vocabulary_status` on `status` — filter by learning status

**Validation**:
- `word_entry_id` is unique (one vocabulary record per word entry)
- `exposure_count` >= 1
- `status` must be one of: `new`, `learning`, `known`
- `last_seen_at` >= `first_seen_at`

## State Machine: user_vocabulary.status

```
                 first lookup
                     |
                     v
                  [ new ]
                     |
              second exposure
                     |
                     v
               [ learning ]
                  |      |
     exposure >= 5 |      | manual "mark as known" (FR-015)
                  |      |
                  v      v
                [ known ]
                     |
              manual "reset to learning" (FR-015)
                     |
                     v
               [ learning ] (exposure_count resets to 0)
```

**Transitions**:
1. **new -> learning**: Triggered by second exposure (exposure_count goes from 1 to 2)
2. **learning -> known**: Triggered when exposure_count >= 5, OR manual override (FR-015)
3. **known -> learning**: Manual override only (FR-015); resets exposure_count to 0

**Underline intensity** (FR-009, User Story 4):
- `new`: light underline (exposure 1)
- `learning` with exposure 1-2: light underline
- `learning` with exposure 3-4: darker underline
- `known`: no underline (word assumed learned)

## SQL Migration

```sql
-- 001_initial_schema.sql

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Works table
CREATE TABLE works (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    author text NOT NULL,
    aozora_url text NOT NULL UNIQUE,
    publish_year smallint,
    token_count int NOT NULL DEFAULT 0 CHECK (token_count >= 0),
    processed_at timestamptz NOT NULL DEFAULT now()
);

-- Word entries table (shared vocabulary items)
CREATE TABLE word_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    base_form text NOT NULL,
    pos text NOT NULL,
    reading text NOT NULL,
    jmdict_id int,
    jmdict_def text,
    ai_explanation text,
    cross_text_examples jsonb NOT NULL DEFAULT '[]'::jsonb,
    work_count int NOT NULL DEFAULT 0 CHECK (work_count >= 0),
    UNIQUE (base_form, pos)
);

-- Tokens table (per-work token sequence)
CREATE TABLE tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_id uuid NOT NULL REFERENCES works(id) ON DELETE CASCADE,
    position int NOT NULL,
    surface text NOT NULL,
    base_form text NOT NULL,
    reading text,
    pos text NOT NULL,
    pos_detail text,
    sentence_text text,
    is_interactive boolean NOT NULL DEFAULT true,
    word_entry_id uuid REFERENCES word_entries(id),
    UNIQUE (work_id, position)
);

CREATE INDEX tokens_word_entry_id ON tokens(word_entry_id);
CREATE INDEX tokens_base_form_pos ON tokens(base_form, pos);

-- User vocabulary table (single user, no user_id)
CREATE TABLE user_vocabulary (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    word_entry_id uuid NOT NULL UNIQUE REFERENCES word_entries(id),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    exposure_count int NOT NULL DEFAULT 1 CHECK (exposure_count >= 1),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    status text NOT NULL DEFAULT 'new'
        CHECK (status IN ('new', 'learning', 'known'))
);

CREATE INDEX user_vocabulary_status ON user_vocabulary(status);

-- Enable Row Level Security (Supabase convention)
ALTER TABLE works ENABLE ROW LEVEL SECURITY;
ALTER TABLE word_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_vocabulary ENABLE ROW LEVEL SECURITY;

-- Allow public read for all tables (single user, no auth)
CREATE POLICY "allow_read" ON works FOR SELECT USING (true);
CREATE POLICY "allow_read" ON word_entries FOR SELECT USING (true);
CREATE POLICY "allow_read" ON tokens FOR SELECT USING (true);
CREATE POLICY "allow_read" ON user_vocabulary FOR SELECT USING (true);

-- Allow public write for user_vocabulary only
CREATE POLICY "allow_insert" ON user_vocabulary FOR INSERT WITH CHECK (true);
CREATE POLICY "allow_update" ON user_vocabulary FOR UPDATE USING (true);
```

## Data Volume Estimates (MVP)

| Table | Rows | Avg Row Size | Total |
|-------|------|-------------|-------|
| works | 5 | ~200 B | ~1 KB |
| tokens | ~50,000 | ~300 B | ~15 MB |
| word_entries | ~5,000 | ~500 B | ~2.5 MB |
| user_vocabulary | 0-5,000 | ~100 B | ~500 KB |

Total database size: ~18 MB (well within Supabase free tier).

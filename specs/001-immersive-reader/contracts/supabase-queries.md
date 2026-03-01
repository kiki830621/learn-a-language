# Supabase Query Contracts

**Date**: 2026-02-28
**Status**: Phase 1 Output
**Consumer**: Next.js reader (frontend)

## Overview

All queries are read-only from the reader's perspective, except
user_vocabulary mutations. Data is pre-computed by the Swift pipeline.

---

## Q1: List All Works (FR-012)

**Used by**: Work list page (`/`)
**Frequency**: On page load, cached (ISR)

```sql
SELECT id, title, author, publish_year, token_count, processed_at
FROM works
ORDER BY publish_year ASC;
```

**Response shape**:
```typescript
type WorkListItem = {
  id: string
  title: string
  author: string
  publish_year: number | null
  token_count: number
  processed_at: string
}
```

---

## Q2: Fetch All Tokens for a Work (FR-001, FR-013)

**Used by**: Reading view (`/works/[id]`)
**Frequency**: On page load, heavily cached (revalidate: 86400)

```sql
SELECT
  t.id,
  t.position,
  t.surface,
  t.base_form,
  t.reading,
  t.pos,
  t.sentence_text,
  t.is_interactive,
  t.word_entry_id
FROM tokens t
WHERE t.work_id = $1
ORDER BY t.position ASC;
```

**Parameters**: `$1` = work UUID
**Response shape**:
```typescript
type Token = {
  id: string
  position: number
  surface: string
  base_form: string
  reading: string | null
  pos: string
  sentence_text: string | null
  is_interactive: boolean
  word_entry_id: string | null
}
```

**Expected volume**: ~10,000 tokens per work (~1-2 MB JSON)

---

## Q3: Fetch Word Entry for Tooltip (FR-002, FR-003, FR-004)

**Used by**: Tooltip component (on hover/click/tap)
**Frequency**: On demand, cached in client state

```sql
SELECT
  id,
  base_form,
  pos,
  reading,
  jmdict_def,
  ai_explanation,
  cross_text_examples,
  work_count
FROM word_entries
WHERE id = $1;
```

**Parameters**: `$1` = word_entry UUID (from token.word_entry_id)
**Response shape**:
```typescript
type WordEntry = {
  id: string
  base_form: string
  pos: string
  reading: string
  jmdict_def: string | null
  ai_explanation: string | null
  cross_text_examples: CrossTextExample[]
  work_count: number
}

type CrossTextExample = {
  work_id: string
  work_title: string
  author: string
  sentence: string
  token_position: number
}
```

---

## Q4: Fetch User Vocabulary (FR-005, FR-007, FR-008, FR-009)

**Used by**: Reading view (client-side, determines hover behavior + underlines)
**Frequency**: On page load, always fresh (no cache)

```sql
SELECT
  uv.word_entry_id,
  uv.exposure_count,
  uv.status
FROM user_vocabulary uv;
```

**Response shape**:
```typescript
type UserVocabRecord = {
  word_entry_id: string
  exposure_count: number
  status: 'new' | 'learning' | 'known'
}
```

**Note**: Fetches ALL vocabulary, not filtered by work. Client maps
word_entry_id to tokens for styling and hover behavior. Expected <5,000
rows = ~200 KB.

---

## M1: Record Word Lookup (FR-005)

**Used by**: Tooltip component (when user first looks up a word)
**Frequency**: On demand

```sql
INSERT INTO user_vocabulary (word_entry_id)
VALUES ($1)
ON CONFLICT (word_entry_id) DO UPDATE
SET
  exposure_count = user_vocabulary.exposure_count + 1,
  last_seen_at = now(),
  status = CASE
    WHEN user_vocabulary.status = 'known' THEN 'known'
    WHEN user_vocabulary.exposure_count + 1 >= 5 THEN 'known'
    WHEN user_vocabulary.exposure_count + 1 >= 2 THEN 'learning'
    ELSE 'new'
  END
RETURNING word_entry_id, exposure_count, status;
```

**Parameters**: `$1` = word_entry UUID
**Behavior**: UPSERT — inserts new record or increments existing.
Status transitions are automatic based on exposure_count.

---

## M2: Mark Word as Known (FR-015)

**Used by**: Tooltip "mark as known" button
**Frequency**: On demand (manual override)

```sql
UPDATE user_vocabulary
SET status = 'known', last_seen_at = now()
WHERE word_entry_id = $1
RETURNING word_entry_id, exposure_count, status;
```

**Parameters**: `$1` = word_entry UUID

---

## M3: Reset Word to Learning (FR-015)

**Used by**: Tooltip "reset to learning" button
**Frequency**: On demand (manual override)

```sql
UPDATE user_vocabulary
SET status = 'learning', exposure_count = 0, last_seen_at = now()
WHERE word_entry_id = $1
RETURNING word_entry_id, exposure_count, status;
```

**Parameters**: `$1` = word_entry UUID

---

## Supabase JS SDK Usage

All queries use `@supabase/supabase-js` client:

```typescript
// Server Component (read-only)
import { createClient } from '@supabase/supabase-js'
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
)

// Q1: List works
const { data } = await supabase
  .from('works')
  .select('id, title, author, publish_year, token_count, processed_at')
  .order('publish_year', { ascending: true })

// Q2: Tokens for a work
const { data } = await supabase
  .from('tokens')
  .select('id, position, surface, base_form, reading, pos, sentence_text, is_interactive, word_entry_id')
  .eq('work_id', workId)
  .order('position', { ascending: true })

// Q3: Word entry
const { data } = await supabase
  .from('word_entries')
  .select('*')
  .eq('id', wordEntryId)
  .single()

// Q4: All user vocabulary (client-side)
const { data } = await supabase
  .from('user_vocabulary')
  .select('word_entry_id, exposure_count, status')

// M1: Record lookup (upsert via RPC)
const { data } = await supabase.rpc('record_word_lookup', {
  p_word_entry_id: wordEntryId
})

// M2: Mark known
const { data } = await supabase
  .from('user_vocabulary')
  .update({ status: 'known', last_seen_at: new Date().toISOString() })
  .eq('word_entry_id', wordEntryId)
  .select()

// M3: Reset to learning
const { data } = await supabase
  .from('user_vocabulary')
  .update({ status: 'learning', exposure_count: 0, last_seen_at: new Date().toISOString() })
  .eq('word_entry_id', wordEntryId)
  .select()
```

**Note**: M1 (upsert with conditional status) is best implemented as a
Postgres function (`record_word_lookup`) called via `supabase.rpc()` to
keep the status transition logic server-side.

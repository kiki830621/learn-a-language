# Learn-a-Language Design

**Date**: 2026-02-28
**Status**: Approved

## Vision

An immersive Japanese reading tool that makes vocabulary acquisition
passive and contextual. Instead of flashcards or vocabulary notebooks,
the reader automatically re-exposes previously looked-up words every
time they appear in new texts. Meaning is conveyed through usage
examples across literary works, not dictionary definitions alone.

Grounded in Wittgenstein's use theory of language: for verbs and
adjectives, meaning is how a word is used, not what a dictionary says.

## System Architecture

Two fully decoupled components:

### 1. Preprocessing Pipeline (Swift CLI)

Processes Aozora Bunko texts offline and writes results to Supabase.

```
Aozora Bunko (.html)
    |
    v
Step 1: Parse HTML + extract furigana + metadata
    |
    v
Step 2: MeCab + UniDic tokenization (via C interop)
    |
    v
Step 3: AI correction (only low-confidence tokens, ~5-10%)
    |
    v
Step 4: JMdict matching (nouns -> definitions)
    |
    v
Step 5: AI explanation generation (verbs/adjectives -> Japanese explanations)
    |
    v
Step 6: Write to Supabase (works, tokens, word_entries)
    |
    v
Step 7: Build cross-text index (after all works processed)
```

### 2. Reader (Next.js on Vercel)

Reads only pre-computed data from Supabase. Zero AI API calls at
read time.

## Data Model (Supabase / PostgreSQL)

### works
| Column | Type | Description |
|--------|------|-------------|
| id | uuid PK | |
| title | text | Work title |
| author | text | Author name |
| aozora_id | text | Aozora Bunko identifier |
| publish_year | int | Original publication year |
| genre | text | Genre classification |
| processed_at | timestamptz | When preprocessing completed |

### tokens
| Column | Type | Description |
|--------|------|-------------|
| id | uuid PK | |
| work_id | uuid FK -> works | Which work this belongs to |
| position | int | Sequential position in text |
| surface | text | Surface form as written |
| base_form | text | Dictionary form (lemma) |
| reading | text | Furigana reading |
| pos | text | Part of speech (noun/verb/adj/particle/...) |
| sentence_text | text | Full sentence containing this token |

### word_entries
| Column | Type | Description |
|--------|------|-------------|
| id | uuid PK | |
| base_form | text UNIQUE | Dictionary form (key) |
| pos | text | Primary part of speech |
| reading | text | Standard reading |
| jmdict_def | text | JMdict English definition (primarily for nouns) |
| ai_explanation | text | AI-generated Japanese explanation |
| cross_text_examples | jsonb | Array of {work, author, sentence} |

### user_vocabulary
| Column | Type | Description |
|--------|------|-------------|
| id | uuid PK | |
| word_id | uuid FK -> word_entries | |
| first_seen_at | timestamptz | When user first looked up this word |
| exposure_count | int | How many times user has seen this word |
| last_seen_at | timestamptz | Most recent exposure |
| status | text | new / learning / known |

## Frontend Interaction Design

### Hover Behavior (Two-Tier)

- **Previously looked-up words**: Hover triggers instant tooltip.
  Visually marked with a subtle underline.
- **New words**: Require click or 0.5s hover delay to show tooltip.
  Looking up a word adds it to user_vocabulary.

### Tooltip Content (Part-of-Speech Dependent)

**Nouns** — Definition first:
```
見当（けんとう）
定義: guess, estimate
> 3篇文章中出現過
```

**Verbs / Adjectives** — Usage examples first:
```
切ない（せつない）

『人間失格』 太宰治
「切ない気持ちが胸に迫ってきた」

『雪國』 川端康成
「それが切なく美しかった」

> JMdict: painful, heartrending
> 全部 7 篇出現過的文章
```

### Visual Indicators

Words in the user's vocabulary (status: learning) are underlined:
- Light underline: recently looked up (exposure 1-2)
- Darker underline: building familiarity (exposure 3-4)
- No underline: assumed learned (exposure 5+)

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Frontend | Next.js (React), deployed on Vercel |
| Database | Supabase (PostgreSQL) |
| Pipeline | Swift CLI (SPM package) |
| Tokenization | MeCab + UniDic via C interop |
| AI | LLM API (correction + explanation generation) |
| Dictionary | JMdict (EDRDG, CC-BY-SA, 190k+ entries) |
| Text Source | Aozora Bunko (public domain) |

## Swift Pipeline Project Structure

```
preprocessing/
├── Package.swift
├── Sources/
│   ├── PipelineCLI/
│   │   └── main.swift
│   ├── Pipeline/
│   │   ├── AozoraParser.swift
│   │   ├── MeCabBridge.swift
│   │   ├── AICorrector.swift
│   │   ├── JMDictMatcher.swift
│   │   ├── AIExplainer.swift
│   │   ├── SupabaseWriter.swift
│   │   └── CrossTextIndexer.swift
│   └── CMeCab/
│       ├── include/
│       │   └── mecab_bridge.h
│       └── mecab_bridge.c
└── Tests/
    └── PipelineTests/
```

## MVP Scope

### In Scope
- Process 5-10 Aozora Bunko works
- Single-article reading with hover tooltips
- Nouns: JMdict definitions
- Verbs/Adjectives: cross-text usage examples
- Instant tooltip for previously looked-up words
- Exposure count tracking
- Underline indicators for learning-in-progress words
- Deploy on Vercel

### Out of Scope (Future)
- Processing all 16,000+ Aozora Bunko works
- Article search/filtering
- Image associations
- User-uploaded custom texts
- Spaced repetition algorithms
- Learning statistics dashboard
- Export/sharing
- User account system

### MVP Works

| Work | Author | Why |
|------|--------|-----|
| 走れメロス | 太宰治 | Short, moderate vocabulary |
| 注文の多い料理店 | 宮沢賢治 | Short, fun, unique vocabulary |
| 羅生門 | 芥川龍之介 | Classic, literary Japanese intro |
| 坊っちゃん (prologue) | 夏目漱石 | Colloquial, vivid |
| 銀河鉄道の夜 | 宮沢賢治 | Poetic, rich in adjectives |

## Success Criteria

1. Can read a full article with hover explanations for any word
2. Previously looked-up words auto-highlight and show instant tooltips
   in subsequent articles
3. Verb/adjective tooltips show at least 2 cross-text usage examples
4. Article load time < 2 seconds (pre-computed data from Supabase)
5. Pipeline processes one short story in < 5 minutes

## Core Principles

See `.specify/memory/constitution.md` for the full constitution:

1. **Preprocessing-First**: All analysis happens offline, stored in Supabase
2. **Meaning is Use**: Part-of-speech determines explanation strategy
3. **Passive Exposure**: Auto re-expose looked-up words, no active review
4. **Cross-Text Linking**: Words link to usage across multiple works
5. **Simplicity**: Single user, Japanese only, YAGNI

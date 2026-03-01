# Implementation Plan: Immersive Japanese Reader

**Branch**: `001-immersive-reader` | **Date**: 2026-02-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-immersive-reader/spec.md`

## Summary

Build an immersive Japanese reading tool for Aozora Bunko literary works.
Two decoupled components: a Swift CLI preprocessing pipeline (MeCab +
UniDic tokenization → AI correction → JMdict matching → AI explanation →
cross-text indexing → Supabase) and a Next.js reader (hover tooltips with
POS-dependent content, passive vocabulary re-exposure, responsive
desktop/mobile). All analysis is pre-computed; zero AI calls at read time.

## Technical Context

**Language/Version**: Swift 5.9+ (pipeline CLI), TypeScript / Next.js 14+ (reader)
**Primary Dependencies**: MeCab + UniDic (C interop), JMdict (XML), Supabase JS SDK, Claude API (pipeline only)
**Storage**: Supabase (PostgreSQL) — works, tokens, word_entries, user_vocabulary
**Testing**: XCTest (Swift pipeline), Vitest + React Testing Library (Next.js)
**Target Platform**: Web (Vercel, responsive desktop + mobile) + macOS (Swift CLI)
**Project Type**: Web application + CLI tool
**Performance Goals**: <2s page load, <100ms tooltip for known words, <5min pipeline per work
**Constraints**: Zero AI API calls at read time, single user (no auth), immutable preprocessing data
**Scale/Scope**: 5 MVP works (~50k tokens total), ~5k unique word entries

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Preprocessing-First | PASS | Pipeline writes to Supabase offline; reader queries only pre-computed data; zero AI calls at read time |
| II. Meaning is Use | PASS | FR-003 (nouns→definition), FR-004 (verbs/adj→usage examples); POS-dependent tooltip content |
| III. Passive Exposure | PASS | FR-007/008 (two-tier hover); FR-005/006 (auto vocabulary tracking); FR-015 (manual override without separate UI) |
| IV. Cross-Text Linking | PASS | FR-010/011 (attributed, navigable cross-text examples); Pipeline Step 7 builds cross-text index |
| V. Simplicity | PASS | Single user, no auth, Aozora Bunko only, 2 components (pipeline + reader), YAGNI |

**Gate Result**: ALL PASS — proceed to Phase 0.

## Project Structure

### Documentation (this feature)

```text
specs/001-immersive-reader/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── supabase-queries.md
│   └── cli-interface.md
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
preprocessing/
├── Package.swift
├── Sources/
│   ├── PipelineCLI/
│   │   └── main.swift
│   ├── Pipeline/
│   │   ├── Models.swift
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

reader/
├── package.json
├── next.config.js
├── src/
│   ├── app/
│   │   ├── layout.tsx
│   │   ├── page.tsx              # Work list
│   │   └── works/[id]/
│   │       └── page.tsx          # Reading view
│   ├── components/
│   │   ├── TokenSpan.tsx
│   │   ├── Tooltip.tsx
│   │   └── WorkList.tsx
│   ├── hooks/
│   │   ├── useUserVocabulary.ts
│   │   └── useTooltip.ts
│   └── lib/
│       ├── supabase.ts
│       └── types.ts
└── tests/

supabase/
└── migrations/
    └── 001_initial_schema.sql
```

**Structure Decision**: Web application pattern with separated backend
(Swift CLI for offline preprocessing) and frontend (Next.js reader).
The two share only the Supabase database as their integration point.

## Constitution Re-Check (Post Phase 1 Design)

*Re-evaluated after data-model.md, contracts/, quickstart.md completed.*

| Principle | Status | Post-Design Evidence |
|-----------|--------|---------------------|
| I. Preprocessing-First | PASS | data-model: tokens/word_entries written by pipeline only; reader queries are all SELECT; no AI calls in supabase-queries.md |
| II. Meaning is Use | PASS | supabase-queries Q3 returns POS + cross_text_examples; contract notes POS-dependent tooltip rendering |
| III. Passive Exposure | PASS | supabase-queries Q4 fetches full user_vocabulary; M1 auto-increments exposure; state machine in data-model enforces transitions |
| IV. Cross-Text Linking | PASS | word_entries.cross_text_examples JSONB stores attributed examples; cli-interface `index` command builds cross-text index |
| V. Simplicity | PASS | No user_id columns; no auth; 4 tables; single CLI + single web app |

**Gate Result**: ALL PASS — proceed to Phase 2 (tasks).

## Complexity Tracking

No constitution violations to justify. Architecture is minimal:
2 components, 1 database, no abstractions beyond what's needed.

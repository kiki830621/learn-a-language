# Tasks: Immersive Japanese Reader

**Input**: Design documents from `/specs/001-immersive-reader/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Included (TDD approach per project workflow rules).

**Organization**: Tasks are grouped by user story to enable independent
implementation and testing. Two codebases: `preprocessing/` (Swift CLI)
and `reader/` (Next.js).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Exact file paths included in all task descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize both project structures, database, and shared config

- [x] T001 Create preprocessing/ Swift SPM project with Package.swift (targets: PipelineCLI, Pipeline, CMeCab) per plan.md structure
- [x] T002 [P] Create reader/ Next.js 14+ project with package.json, next.config.js, tsconfig.json, and App Router structure per plan.md
- [x] T003 [P] Create supabase/migrations/001_initial_schema.sql from data-model.md SQL migration
- [x] T004 [P] Create .env.local template and add to .gitignore; document required environment variables per contracts/cli-interface.md
- [x] T005 [P] Download jmdict-eng.json to preprocessing/data/ per quickstart.md instructions

---

## Phase 2: Foundational (Pipeline Core + Reader Infra)

**Purpose**: Core pipeline modules and reader infrastructure that ALL user stories depend on

**CRITICAL**: No user story work can begin until this phase is complete

### Pipeline: C Bridge & Data Types

- [x] T006 Create CMeCab system library target with shim header and module.modulemap in preprocessing/Sources/CMeCab/include/
- [x] T007 Create Pipeline/Models.swift with shared data types (ParsedWork, Token, WordEntry structs) in preprocessing/Sources/Pipeline/Models.swift

### Pipeline: Aozora Parser (TDD)

- [x] T008 Write failing tests for AozoraParser (Shift_JIS decoding, ruby extraction, main_text isolation, notes stripping) in preprocessing/Tests/PipelineTests/AozoraParserTests.swift
- [x] T009 Implement AozoraParser using Foundation XMLParser (SAX) per research.md Section 2 in preprocessing/Sources/Pipeline/AozoraParser.swift

### Pipeline: MeCab Tokenizer (TDD)

- [x] T010 Write failing tests for MeCabBridge (tokenization, surface/length handling, UniDic field extraction) in preprocessing/Tests/PipelineTests/MeCabBridgeTests.swift
- [x] T011 Implement MeCabBridge wrapping mecab_new2/mecab_sparse_tonode per research.md Section 1 in preprocessing/Sources/Pipeline/MeCabBridge.swift

### Pipeline: JMdict Matcher (TDD)

- [x] T012 Write failing tests for JMDictMatcher (JSON loading, base_form lookup, POS mapping) in preprocessing/Tests/PipelineTests/JMDictMatcherTests.swift
- [x] T013 Implement JMDictMatcher parsing jmdict-simplified JSON per research.md Section 3 in preprocessing/Sources/Pipeline/JMDictMatcher.swift

### Pipeline: Supabase Writer (TDD)

- [x] T014 Write failing tests for SupabaseWriter (connection, bulk insert via UNNEST, work/token/word_entry upsert) in preprocessing/Tests/PipelineTests/SupabaseWriterTests.swift
- [x] T015 Implement SupabaseWriter using PostgresNIO with TLS per research.md Section 4 in preprocessing/Sources/Pipeline/SupabaseWriter.swift

### Reader: Client Infrastructure

- [x] T016 [P] Create Supabase server client (server-only) and browser client in reader/src/lib/supabase.ts per research.md Section 5
- [x] T017 [P] Create shared TypeScript types (WorkListItem, Token, WordEntry, CrossTextExample, UserVocabRecord) in reader/src/lib/types.ts per contracts/supabase-queries.md

**Checkpoint**: Pipeline can parse HTML, tokenize, match dictionary, and write to Supabase. Reader has DB client and type definitions.

---

## Phase 3: User Story 1 - Read and Look Up Words (Priority: P1) MVP

**Goal**: User can open a processed work, see all words individually
interactive, hover/tap any word to see a tooltip with reading and meaning.

**Independent Test**: Open a processed work → hover over any word →
tooltip shows reading (furigana) + definition (noun) or explanation (verb/adj).

### Pipeline: AI Steps (TDD)

- [x] T018 [P] [US1] Write failing tests for AICorrector (low-confidence token detection, Claude API call mock, correction merge) in preprocessing/Tests/PipelineTests/AICorrectorTests.swift
- [x] T019 [P] [US1] Write failing tests for AIExplainer (verb/adj filtering, Claude API call mock, explanation format) in preprocessing/Tests/PipelineTests/AIExplainerTests.swift
- [x] T020 [US1] Implement AICorrector calling Claude API for low-confidence tokens per plan.md Step 3 in preprocessing/Sources/Pipeline/AICorrector.swift
- [x] T021 [US1] Implement AIExplainer generating Japanese explanations for verbs/adjectives per plan.md Step 5 in preprocessing/Sources/Pipeline/AIExplainer.swift

### Pipeline: CLI `process` Command

- [x] T022 [US1] Implement `process` command orchestrating Steps 1-6 in preprocessing/Sources/PipelineCLI/main.swift per contracts/cli-interface.md
- [x] T023 [US1] Process first test work (走れメロス) with --skip-ai --dry-run and verify pipeline output

### Reader: Work List (TDD)

- [x] T024 [P] [US1] Write failing test for WorkList component (renders titles, authors, links) in reader/tests/components/WorkList.test.tsx
- [x] T025 [US1] Implement WorkList component fetching Q1 query in reader/src/components/WorkList.tsx per contracts/supabase-queries.md
- [x] T026 [US1] Implement work list page (Server Component with ISR) in reader/src/app/page.tsx

### Reader: Reading View & Token Display (TDD)

- [x] T027 [P] [US1] Write failing test for TokenSpan component (renders surface text, handles interactive/non-interactive) in reader/tests/components/TokenSpan.test.tsx
- [x] T028 [US1] Implement TokenSpan component in reader/src/components/TokenSpan.tsx
- [x] T029 [US1] Implement reading view page fetching Q2 tokens (Server Component) in reader/src/app/works/[id]/page.tsx
- [x] T030 [US1] Implement root layout with global styles and Japanese font in reader/src/app/layout.tsx

### Reader: Tooltip (TDD)

- [x] T031 [US1] Write failing test for Tooltip component (displays reading, POS-dependent content: noun→def, verb→examples) in reader/tests/components/Tooltip.test.tsx
- [x] T032 [US1] Implement Tooltip component using Floating UI with useClick() per research.md Section 5 in reader/src/components/Tooltip.tsx
- [x] T033 [US1] Implement useTooltip hook (fetch Q3 word entry, manage open/close state) in reader/src/hooks/useTooltip.ts

### Reader: Word Lookup Recording

- [x] T034 [US1] Create record_word_lookup Postgres function (M1 upsert with status transition) in supabase/migrations/002_record_word_lookup.sql per contracts/supabase-queries.md
- [x] T035 [US1] Wire tooltip click to call record_word_lookup via supabase.rpc() in reader/src/components/Tooltip.tsx

### Mobile Support (FR-014)

- [x] T036 [US1] Add tap interaction (useClick from Floating UI) for mobile/tablet in reader/src/hooks/useTooltip.ts
- [x] T037 [US1] Add responsive layout (reading width, font size, touch targets) in reader/src/app/works/[id]/page.tsx

**Checkpoint**: US1 complete. Can open a work, see all tokens, hover/tap to see tooltip with reading + POS-dependent content. Word lookups recorded.

---

## Phase 4: User Story 2 - Passive Vocabulary Re-Exposure (Priority: P2)

**Goal**: Previously looked-up words show instant tooltips and are visually
distinguished. Exposure count tracked. Manual override available.

**Independent Test**: Look up a word in Work A → open Work B containing
same word → word is underlined → hover shows instant tooltip.

### Reader: User Vocabulary State (TDD)

- [x] T038 [US2] Write failing test for useUserVocabulary hook (fetches Q4, provides lookup map, handles mutations) in reader/tests/hooks/useUserVocabulary.test.ts
- [x] T039 [US2] Implement useUserVocabulary hook fetching all user_vocabulary (client-side, always fresh) in reader/src/hooks/useUserVocabulary.ts

### Reader: Two-Tier Hover Behavior (FR-007, FR-008)

- [x] T040 [US2] Update useTooltip hook: known words → useHover({ mouseOnly: true, delay: 0 }), unknown words → useHover({ delay: 500 }) or useClick() in reader/src/hooks/useTooltip.ts
- [x] T041 [US2] Update TokenSpan to accept vocabulary status and apply conditional hover behavior in reader/src/components/TokenSpan.tsx

### Reader: Underline Styling (FR-009)

- [x] T042 [US2] Add underline CSS for vocabulary words (status: new/learning → underline, known → no underline) in reader/src/components/TokenSpan.tsx

### Reader: Tooltip Bridging (FR-016)

- [x] T043 [US2] Add safePolygon() with ~300ms grace period to useTooltip hook for hover-to-tooltip bridging in reader/src/hooks/useTooltip.ts

### Reader: Manual Override (FR-015)

- [x] T044 [US2] Add "mark as known" and "reset to learning" buttons in Tooltip component calling M2/M3 mutations in reader/src/components/Tooltip.tsx
- [x] T045 [US2] Implement optimistic UI updates in useUserVocabulary for manual status changes in reader/src/hooks/useUserVocabulary.ts

**Checkpoint**: US1 + US2 complete. Words re-expose passively across works with visual indicators. Manual override works.

---

## Phase 5: User Story 3 - Cross-Text Usage Examples (Priority: P3)

**Goal**: Verb/adjective tooltips show attributed usage examples from other
works. Examples are navigable.

**Independent Test**: Process 3+ works with a common verb → hover over
verb → tooltip shows sentences from other works with author/title →
click example → navigate to that passage.

### Pipeline: Cross-Text Indexer (TDD)

- [x] T046 [US3] Write failing tests for CrossTextIndexer (scans all works, groups by base_form+pos, builds example array) in preprocessing/Tests/PipelineTests/CrossTextIndexerTests.swift
- [x] T047 [US3] Implement CrossTextIndexer updating word_entries.cross_text_examples JSONB in preprocessing/Sources/Pipeline/CrossTextIndexer.swift
- [x] T048 [US3] Implement `index` command in CLI dispatching CrossTextIndexer in preprocessing/Sources/PipelineCLI/main.swift per contracts/cli-interface.md

### Pipeline: Process All MVP Works

- [ ] T049 [US3] Process all 5 MVP works (走れメロス, 注文の多い料理店, 羅生門, 坊っちゃん, 銀河鉄道の夜) and run `index` per quickstart.md

### Reader: Cross-Text Examples Display

- [x] T050 [US3] Update Tooltip to render cross_text_examples with work title + author attribution for verbs/adjectives (FR-010) in reader/src/components/Tooltip.tsx
- [x] T051 [US3] Implement cross-text example navigation: click example → navigate to /works/[id]?position=N (FR-011) in reader/src/components/Tooltip.tsx
- [x] T052 [US3] Handle scroll-to-position on reading view when ?position= query param is present in reader/src/app/works/[id]/page.tsx

**Checkpoint**: US1 + US2 + US3 complete. Verbs/adjectives show rich cross-text examples with navigation.

---

## Phase 6: User Story 4 - Vocabulary Progress Indicators (Priority: P4)

**Goal**: Underline intensity reflects exposure count, providing visual
feedback on learning progress.

**Independent Test**: Look up a word → light underline (exposure 1-2) →
look up again → darker underline (exposure 3-4) → look up 5+ times →
underline disappears.

### Reader: Graduated Underline Intensity

- [x] T053 [US4] Implement graduated underline styles based on exposure_count (1-2: light, 3-4: darker, 5+: none) in reader/src/components/TokenSpan.tsx
- [x] T054 [US4] Write test for graduated underline logic (exposure count → CSS class mapping) in reader/tests/components/TokenSpan.test.tsx

**Checkpoint**: All 4 user stories complete. Full reading experience with passive vocabulary re-exposure and visual progress.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [x] T055 [P] Implement `list` command showing all processed works in preprocessing/Sources/PipelineCLI/main.swift per contracts/cli-interface.md
- [x] T056 [P] Add error handling and loading states to reader pages (empty work list, failed token fetch, tooltip error) in reader/src/app/
- [x] T057 Performance: add unstable_cache (revalidate: 86400) for token queries in reader/src/app/works/[id]/page.tsx
- [ ] T058 [P] Run quickstart.md validation end-to-end (fresh setup → process → read → verify tooltip)
- [ ] T059 Deploy reader to Vercel and verify production build

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 — core reading experience
- **US2 (Phase 4)**: Depends on US1 (needs working tooltip and word lookup)
- **US3 (Phase 5)**: Depends on Phase 2 (pipeline) + US1 (reader). Can start pipeline tasks (T046-T049) in parallel with US2.
- **US4 (Phase 6)**: Depends on US2 (needs underline styling infrastructure)
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

```
Phase 1: Setup
    │
    v
Phase 2: Foundational ─────────────────────────┐
    │                                           │
    v                                           v
Phase 3: US1 (Read + Look Up)    T046-T049: US3 pipeline tasks
    │                             (can start after Phase 2)
    v                                    │
Phase 4: US2 (Passive Re-Exposure)       │
    │                                    │
    v                                    v
Phase 5: US3 reader tasks ◄──── US3 pipeline complete
    │
    v
Phase 6: US4 (Progress Indicators)
    │
    v
Phase 7: Polish
```

### Within Each User Story

1. Tests MUST be written and FAIL before implementation (TDD)
2. Pipeline modules before reader components (data must exist)
3. Core components before integration
4. Story complete before moving to next priority

### Parallel Opportunities

**Phase 1**: T002, T003, T004, T005 all run in parallel after T001
**Phase 2**: T008+T009 || T010+T011 || T012+T013 (different modules, no deps)
**Phase 3**: T018 || T019 (AI tests), T024 || T027 (different components)
**Phase 4-5**: US3 pipeline tasks (T046-T049) can overlap with US2 reader tasks

---

## Parallel Example: Phase 2 Foundational

```
# Launch all TDD pairs in parallel (different modules):
Agent 1: T008 → T009  (AozoraParser tests → impl)
Agent 2: T010 → T011  (MeCabBridge tests → impl)
Agent 3: T012 → T013  (JMDictMatcher tests → impl)
Agent 4: T016 + T017  (Reader infra: supabase.ts + types.ts)

# Then sequential:
T014 → T015  (SupabaseWriter depends on Models.swift from T007)
```

## Parallel Example: Phase 3 US1

```
# Pipeline AI steps in parallel:
Agent 1: T018 → T020  (AICorrector tests → impl)
Agent 2: T019 → T021  (AIExplainer tests → impl)

# Reader components in parallel:
Agent 3: T024 → T025  (WorkList test → impl)
Agent 4: T027 → T028  (TokenSpan test → impl)

# Then sequential:
T022 (CLI process) → T023 (process test work)
T031 → T032 → T033 (Tooltip test → impl → hook)
T029 → T030 (reading view → layout)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1
4. **STOP and VALIDATE**: Open a processed work, hover words, verify tooltips
5. Deploy reader to Vercel for real-world testing

### Incremental Delivery

1. Setup + Foundational → Pipeline and reader infrastructure ready
2. US1 → Can read and look up words → **Deploy (MVP!)**
3. US2 → Passive re-exposure across works → Deploy
4. US3 → Cross-text usage examples → Deploy
5. US4 → Visual progress indicators → Deploy
6. Each story adds value without breaking previous stories

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Two codebases: `preprocessing/` (Swift) and `reader/` (Next.js)
- Pipeline tasks must complete before dependent reader tasks (data must exist in Supabase)
- Commit after each task or logical TDD pair (test + implementation)
- Stop at any checkpoint to validate story independently

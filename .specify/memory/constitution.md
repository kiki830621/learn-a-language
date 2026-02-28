<!--
Sync Impact Report
==================
Version change: N/A (template) → 1.0.0
Modified principles: N/A (initial ratification)
Added sections:
  - 5 Core Principles (Preprocessing-First, Meaning is Use, Passive Exposure,
    Cross-Text Linking, Simplicity)
  - Technology Stack
  - Development Workflow
  - Governance
Removed sections: All template placeholders replaced
Templates requiring updates:
  - .specify/templates/plan-template.md: ✅ compatible (Constitution Check section)
  - .specify/templates/spec-template.md: ✅ compatible (no principle-specific refs)
  - .specify/templates/tasks-template.md: ✅ compatible (phase structure fits)
Follow-up TODOs: None
-->

# Learn-a-Language Constitution

## Core Principles

### I. Preprocessing-First

All text analysis MUST happen ahead of time, never at read-time.
Raw texts (Aozora Bunko) are processed through a pipeline
(MeCab + UniDic tokenization → AI correction → dictionary matching →
cross-text indexing) and the results stored in Supabase.

- The reader frontend MUST query only pre-computed data
- Zero AI API calls at hover/read time
- New texts MUST go through the full pipeline before becoming readable
- Preprocessing accuracy target: 97%+ tokenization via MeCab + AI correction

Rationale: Preprocessing trades upfront compute cost for read-time speed
and accuracy. A 10-second preprocessing delay per text is acceptable;
a 500ms hover delay is not.

### II. Meaning is Use (Wittgenstein)

Word explanations MUST be determined by part of speech:

- **Nouns**: Dictionary definition first (JMdict), usage examples secondary
- **Verbs / Adjectives**: Usage examples from other texts first,
  dictionary definition collapsed/secondary
- **All words**: Reading (ふりがな) MUST always be shown

This principle rejects the assumption that a dictionary definition
adequately conveys meaning for all word types. For verbs and adjectives,
meaning emerges from seeing the word used across multiple contexts.

### III. Passive Exposure

The system MUST automatically re-expose previously looked-up words
without requiring user action.

- Words the user has looked up before: hover triggers instant tooltip
- Words never looked up: require click or 0.5s hover delay
- The user MUST NOT need to open a vocabulary list, flashcard deck,
  or any separate review interface
- Exposure count per word MUST be tracked (target: 5+ encounters
  per word, per language acquisition research)

Rationale: People do not use vocabulary notebooks. Passive, in-context
re-exposure removes the friction that prevents vocabulary retention.

### IV. Cross-Text Linking

Every word occurrence MUST be linked to its occurrences in other texts.

- Tooltip for verbs/adjectives shows sentences from other works
  where the word appears, with author and work title
- Links are navigable: clicking a cross-text reference opens that
  passage in context
- Cross-text index is built during preprocessing and stored in Supabase

Rationale: A single occurrence teaches spelling; multiple occurrences
across different authors and contexts teach meaning.

### V. Simplicity

- Build for a single user (the author) learning Japanese
- Start with Aozora Bunko texts only
- No user authentication, no multi-tenancy, no i18n
- YAGNI: do not build features until they are needed
- Prefer fewer moving parts over architectural elegance

## Technology Stack

- **Frontend**: Next.js (React), deployed on Vercel
- **Database**: Supabase (PostgreSQL) for preprocessed text data,
  word index, cross-text links, and user vocabulary state
- **Preprocessing pipeline**: Swift (MeCab via C interop + UniDic
  for tokenization, LLM API for correction and explanation generation)
- **Dictionary data**: JMdict (EDRDG, CC-BY-SA) for base definitions
- **Text source**: Aozora Bunko (public domain Japanese literature)

## Development Workflow

- TDD: write tests first, verify they fail, then implement
- Immutable data patterns: preprocessing creates new records,
  never mutates existing ones
- Commits follow conventional format (feat/fix/refactor/docs/test/chore)
- Code review via agent after each significant change
- Constitution compliance checked at plan phase and before merge

## Governance

This constitution supersedes all other development practices for
this project. Amendments require:

1. Documentation of the proposed change and rationale
2. Version bump following semver (MAJOR: principle removal/redefinition,
   MINOR: new principle or material expansion, PATCH: clarification)
3. Update of this file and any affected templates

All implementation plans MUST pass a Constitution Check verifying
alignment with these principles before work begins.

**Version**: 1.0.0 | **Ratified**: 2026-02-28 | **Last Amended**: 2026-02-28

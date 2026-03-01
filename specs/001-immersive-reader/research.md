# Phase 0 Research: Immersive Japanese Reader

**Date**: 2026-02-28
**Status**: Complete

## 1. MeCab + Swift C Interop

**Decision**: Use SPM `systemLibrary` target with manual include/lib paths.

**Rationale**: MeCab has no `.pc` (pkg-config) file from Homebrew. The
standard approach is a shim header + `module.modulemap` wrapping the
system C library, with `unsafeFlags` pointing to Homebrew paths. This is
fine for a CLI tool (not a redistributable library).

**Key findings**:
- Install: `brew install mecab mecab-unidic`
- SPM: `systemLibrary(name: "CMeCab")` with `shim.h` → `#include <mecab.h>`
- API: `mecab_new2("")` → `mecab_sparse_tonode(tagger, cStr)` → iterate
  `mecab_node_t` linked list
- **Critical**: `surface` is NOT null-terminated — must use `length` field
  to extract bytes. `feature` IS null-terminated.
- UniDic feature fields: `pos1[0], pos2[1], ..., lemma[7], ..., pron[9],
  orthBase[10]` (17 fields total, differs from IPADic's 9)
- Thread safety: one tagger per thread (not thread-safe)
- Memory: node data invalidated on next parse call — copy all data out
  immediately

**Alternatives considered**:
- novi/mecab-swift wrapper: adds dependency for minimal benefit
- Kuromoji.js: rejected for accuracy (~85-90% for literary text vs 97%+)

## 2. Aozora Bunko HTML Format

**Decision**: Parse XHTML with Foundation's XMLParser (SAX), extract ruby
annotations and plain text, strip formatting markup.

**Rationale**: Aozora Bunko files are well-structured XHTML 1.1 with
consistent annotation patterns. SAX parsing is efficient and handles the
document size well.

**Key findings**:
- **Encoding**: Files declare `charset=utf-8` in recent XHTML versions;
  older files use Shift_JIS (detect via meta tag, convert with `iconv`)
- **Ruby/Furigana**: `<ruby><rb>漢字</rb><rp>(</rp><rt>かんじ</rt><rp>)</rp></ruby>`
- **Main text body**: Between `<div class="main_text">` and the bibliographic
  info section (marked by `<div class="bibliographical_information">`)
- **Paragraph structure**: `<br />` for line breaks within paragraphs;
  `<div class="jisage_N">` for indentation
- **Headings**: `<h3 class="o-midashi">`, `<h4 class="naka-midashi">`,
  `<h5 class="ko-midashi">` with `midashi_anchor` IDs
- **Emphasis**: `<em class="sesame_dot">` (傍点), `<span class="futoji">`
  (bold), `<span class="shatai">` (italic)
- **Notes**: `<span class="notes">［＃改ページ］</span>` — strip these
- **External characters**: `<img class="gaiji" ...>` — replace with
  placeholder or Unicode equivalent
- **File path**: `cards/{person_id}/files/{work_id}_{version}.html`
- **Metadata**: Title in `<title>`, author in bibliographic section

**Alternatives considered**:
- SwiftSoup (HTML parser): heavier dependency; XHTML is valid XML so
  Foundation XMLParser suffices
- Regex parsing: fragile, not recommended for structured HTML

## 3. JMdict Parsing in Swift

**Decision**: Use jmdict-simplified JSON releases (pre-converted from XML),
parse with `JSONDecoder`, index into in-memory `Dictionary`.

**Rationale**: JMdict raw XML uses custom DTD entity references (`&v1;`,
`&n;`) that Foundation's `XMLParser` cannot resolve (known bug SR-14581).
The jmdict-simplified project publishes weekly JSON releases (~10.7 MB
compressed) with a clean structure, eliminating the entity problem entirely.

**Key findings**:
- **Source**: https://github.com/scriptin/jmdict-simplified/releases
- **File**: `jmdict-eng-{version}.json.tgz` (~10.7 MB compressed)
- **Common-only variant**: `jmdict-eng-common-*.json.tgz` (~1.35 MB)
- **Structure**: Array of entries, each with `kanji[]`, `kana[]`, `sense[]`
  where sense contains `partOfSpeech[]` and `gloss[]{lang, text}`
- **POS tags**: Use JMdict entity names: `n`, `v1`, `v5r`, `adj-i`, `adj-na`
- **MeCab → JMdict mapping**: Match `base_form` (field[7]) against `kanji`
  or `kana` forms; disambiguate by POS score when multiple entries match
- **POS inheritance**: If a sense has no POS tags, it inherits from the
  previous sense (JMdict convention)
- **Total entries**: ~190,000 in full; ~30,000 in common-only

**Alternatives considered**:
- Raw XML + SAX with entity preprocessing: works but requires manual
  entity replacement step; more complex for same result
- SQLite/FTS5 index: overkill for 5 MVP works; in-memory Dictionary
  suffices. Can add later if lookup speed becomes an issue.

## 4. Supabase from Swift CLI

**Decision**: Use PostgresNIO (direct Postgres connection) for bulk
inserts during preprocessing. Use supabase-swift SDK as fallback option.

**Rationale**: PostgresNIO provides direct Postgres access with UNNEST
bulk inserts (2x+ faster than REST), works on macOS and Linux, and avoids
PostgREST HTTP overhead. For a CLI tool inserting thousands of tokens per
work, direct Postgres is the most efficient approach.

**Key findings**:
- **PostgresNIO**: `vapor/postgres-nio` v1.21+, SPM package, TLS required
  for Supabase connection
- **Connection**: `db.{ref}.supabase.co:5432`, credentials in Supabase
  Dashboard → Settings → Database
- **Bulk insert pattern**: `INSERT INTO tokens (...) SELECT * FROM
  UNNEST($1::uuid[], $2::text[], ...)` — batch 1,000-10,000 rows
- **Auth**: Use Postgres username/password directly (not Supabase API keys)
- **Environment vars**: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`,
  `PGDATABASE` — standard Postgres conventions
- **Client lifecycle**: `PostgresClient.run()` task must be alive during
  queries; cancel task group to shut down
- **supabase-swift fallback**: Works on macOS (officially supported),
  REST-based, batch in chunks of 500 rows via JSON POST

**Alternatives considered**:
- supabase-swift only: simpler but slower for bulk inserts (HTTP overhead)
- Raw URLSession + REST API: no external dependency but very verbose
- postgres-kit: higher-level wrapper on PostgresNIO, adds unnecessary
  abstraction for a CLI tool

## 5. Next.js + Supabase Reader Patterns

**Decision**: `@supabase/supabase-js` directly (no `@supabase/ssr`),
Server Components for reads, Server Actions for writes, Floating UI for
tooltips.

**Rationale**: No auth needed (single user), so `@supabase/ssr` cookie
management adds zero value. Server Components fetch pre-computed data
directly. Floating UI provides the exact hover/click/tap composition
needed for the two-tier tooltip behavior.

**Key findings**:
- **Supabase client**: Plain `@supabase/supabase-js` with `server-only`
  guard for Server Components; separate browser client for Client Components
- **Data fetching**: Server Components with `unstable_cache` (revalidate:
  86400) or ISR via `generateStaticParams` + `revalidate` export
- **Caching split**: Work tokens heavily cached (pre-computed, rarely
  changes); user_vocabulary always dynamic (fetched client-side)
- **Pagination**: Fetch all tokens for a work in one query (~1-2 MB for
  10,000 tokens); use DOM virtualization (`@tanstack/virtual` or
  `react-window`) for rendering performance
- **Real-time**: Not needed. Optimistic UI + fire-and-forget writes for
  vocabulary mutations. Single user = no collaboration sync needed.
- **Tooltip library**: Floating UI (`@floating-ui/react`) with:
  - `useHover({ mouseOnly: true, delay: isKnown ? 0 : 500 })` for desktop
  - `useClick()` for mobile tap (composes via `useInteractions`)
  - `safePolygon()` for ~300ms grace period (FR-016)
  - Popover pattern (not Tooltip role) because tooltip is interactive
- **Vocabulary writes**: Server Actions called from Client Components;
  optimistic state update in React, async Supabase write

**Alternatives considered**:
- `@supabase/ssr`: unnecessary without auth
- Radix UI Tooltip: explicitly does not work on touch devices
- Tippy.js: legacy, Floating UI is the successor
- API routes for reads: adds unnecessary HTTP round-trip
- Supabase Realtime: unnecessary for single user, adds cost/complexity

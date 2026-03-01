# Feature Specification: Immersive Japanese Reader

**Feature Branch**: `001-immersive-reader`
**Created**: 2026-02-28
**Status**: Draft
**Input**: User description: "Immersive Japanese reading tool with hover tooltips and passive vocabulary acquisition for Aozora Bunko texts"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read and Look Up Words (Priority: P1)

As a Japanese learner, I want to read a literary text and instantly see
the meaning of any word I encounter, so that I can read without
interrupting my flow to open a separate dictionary.

I select an article from a list of available works. The text renders
with every word individually addressable. When I hover over or click a
word, a tooltip appears showing:
- The word's reading (furigana)
- An explanation appropriate to the word type

**Why this priority**: This is the core experience. Without it, nothing
else matters. A reader that can display text and show word meanings is
the minimum viable product.

**Independent Test**: Can be fully tested by opening a processed work,
hovering over any word, and verifying a tooltip with reading and
meaning appears. Delivers value as a standalone dictionary-integrated
reader.

**Acceptance Scenarios**:

1. **Given** a processed literary work is available, **When** the user
   opens it, **Then** the full text is displayed with every word
   individually interactive.
2. **Given** the user hovers over a noun, **When** the tooltip appears,
   **Then** it shows: reading (furigana), dictionary definition, and
   count of other works where this word appears.
3. **Given** the user hovers over a verb or adjective, **When** the
   tooltip appears, **Then** it shows: reading, usage examples from
   other literary works (author + sentence), with dictionary definition
   available but secondary.
4. **Given** the user clicks a word they have never looked up, **When**
   the tooltip appears, **Then** the word is recorded in their
   personal vocabulary.
5. **Given** the user is on a mobile/tablet device, **When** they tap
   any word, **Then** the tooltip appears immediately regardless of
   whether the word was previously looked up.

---

### User Story 2 - Passive Vocabulary Re-Exposure (Priority: P2)

As a Japanese learner, I want words I have previously looked up to
automatically show their meaning whenever I encounter them again,
so that I learn vocabulary passively through repeated contextual
exposure without needing to maintain flashcards or vocabulary lists.

Words I have looked up before are visually distinguished in the text
(subtle underline). Hovering over them instantly shows the tooltip
(no delay). The system tracks how many times I have been exposed to
each word.

**Why this priority**: This is the differentiating feature grounded in
language acquisition theory (5+ exposures to learn a word). Without
it, the tool is just another dictionary — with it, it becomes a
learning system.

**Independent Test**: Can be tested by looking up a word in one work,
then opening a different work containing the same word, and verifying
the word is visually marked and shows an instant tooltip.

**Acceptance Scenarios**:

1. **Given** the user has previously looked up a word, **When** that
   word appears in any text, **Then** it is visually distinguished
   with a subtle underline.
2. **Given** the user hovers over a previously looked-up word, **When**
   the tooltip appears, **Then** it appears instantly (no delay)
   and the exposure count increments.
3. **Given** a word has never been looked up, **When** the user hovers
   over it, **Then** the tooltip requires either a click or a brief
   hover delay (0.5 seconds) before appearing.
4. **Given** the user has been exposed to a word 5 or more times,
   **Then** the visual underline disappears (word assumed learned).
5. **Given** the user views a tooltip for any vocabulary word, **When**
   they choose to manually mark it as "known", **Then** the word's
   underline disappears immediately and future encounters treat it
   as learned.
6. **Given** the user has a word marked as "known" (manually or by
   exposure), **When** they choose to reset it to "learning", **Then**
   the underline reappears and the exposure count resets to 0.

---

### User Story 3 - Cross-Text Usage Examples (Priority: P3)

As a Japanese learner, I want to see how a word is used across
multiple literary works by different authors, so that I understand
its meaning through varied contexts rather than a single definition
(following the principle that meaning emerges from use).

When viewing examples for a verb or adjective, I see sentences from
other works where the same word appears, each attributed to its
author and work title. I can click an example to navigate to that
passage in context.

**Why this priority**: This implements the Wittgensteinian principle
that meaning is use. Cross-text examples are what make verbs and
adjectives truly comprehensible, but the feature requires multiple
works to be processed first.

**Independent Test**: Can be tested by processing at least 3 works
containing a common verb, then verifying the verb's tooltip shows
usage examples from each work with author attribution.

**Acceptance Scenarios**:

1. **Given** a verb appears in 3+ processed works, **When** the user
   views its tooltip, **Then** at least 2 cross-text examples are
   shown with work title and author.
2. **Given** the user clicks a cross-text example, **When** the
   navigation occurs, **Then** the target work opens with the
   relevant passage visible.
3. **Given** an adjective appears in multiple works, **When** the
   user views its tooltip, **Then** usage examples are shown before
   the dictionary definition.

---

### User Story 4 - Vocabulary Progress Indicators (Priority: P4)

As a Japanese learner, I want to see visual cues in the text that
reflect how well I know each word, so that I can passively notice
which words I am still learning without checking a separate dashboard.

Words in my vocabulary have different underline intensities based on
exposure count: light for recently discovered, stronger for building
familiarity, and no underline once assumed learned.

**Why this priority**: A polish feature that enhances the passive
exposure experience. Not strictly required for the tool to be useful,
but adds a satisfying feedback loop.

**Independent Test**: Can be tested by looking up a word and verifying
the underline appearance changes as the exposure count increases
across multiple reading sessions.

**Acceptance Scenarios**:

1. **Given** a word has been looked up 1-2 times, **When** it appears
   in any text, **Then** it has a light underline.
2. **Given** a word has been looked up 3-4 times, **When** it appears
   in any text, **Then** it has a darker/stronger underline.
3. **Given** a word has been looked up 5+ times, **When** it appears
   in any text, **Then** no underline is shown (assumed learned).

---

### Edge Cases

- What happens when a word has no dictionary entry and no cross-text
  examples? Display the reading (furigana) with an indication that
  no definition is available.
- What happens when the user hovers between two closely positioned
  words? Only the word directly under the cursor should trigger.
- What happens when a word has multiple possible readings? Display
  the reading as determined by the text's context (preprocessing
  resolves ambiguity ahead of time).
- How does the system handle compound words that may be tokenized
  differently? The preprocessing pipeline determines word boundaries;
  the reader displays whatever the pipeline produced.
- What happens when the text contains non-Japanese characters
  (punctuation, numbers, romaji)? These are rendered as plain text
  with no tooltip interaction.
- How does the tooltip behave on touch devices when the user taps
  outside the tooltip? The tooltip dismisses on tap-outside or on
  tapping a different word.
- What happens when the user quickly moves the cursor across multiple
  words on desktop? Only the word currently under the cursor triggers;
  the previous tooltip dismisses after the ~300ms grace period if the
  cursor does not enter it.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST display literary works as readable text
  with every Japanese word individually interactive.
- **FR-002**: System MUST show a tooltip containing the word's reading
  (furigana) for any interactive word.
- **FR-003**: For nouns, the tooltip MUST prioritize showing a
  dictionary definition, with cross-text examples secondary.
- **FR-004**: For verbs and adjectives, the tooltip MUST prioritize
  showing cross-text usage examples from other works, with dictionary
  definition available but collapsed/secondary.
- **FR-005**: System MUST record each word lookup in the user's
  personal vocabulary with a timestamp.
- **FR-006**: System MUST track the number of times the user has been
  exposed to each vocabulary word.
- **FR-007**: On desktop, previously looked-up words MUST show tooltips
  instantly on hover (no delay). On mobile/tablet, a single tap MUST
  show the tooltip.
- **FR-008**: On desktop, words never looked up MUST require a click or
  0.5-second hover delay before showing the tooltip. On mobile/tablet,
  a single tap MUST show the tooltip (no distinction between known and
  unknown words for tap interaction).
- **FR-014**: The reader interface MUST be fully responsive, adapting
  layout and interaction modes for desktop (hover + click) and
  mobile/tablet (tap) devices.
- **FR-016**: On desktop, the tooltip MUST remain visible while the
  cursor is over the tooltip itself (hover-to-tooltip bridging with
  ~300ms grace period). The tooltip dismisses when the cursor leaves
  both the word and the tooltip area.
- **FR-009**: Previously looked-up words MUST be visually
  distinguished in the text via underline styling that reflects
  exposure count.
- **FR-015**: The tooltip MUST provide an option for the user to
  manually mark a word as "known" (skipping the 5-exposure threshold)
  or reset a word to "learning" status. The system otherwise operates
  fully automatically with no separate vocabulary management interface.
- **FR-010**: Cross-text examples MUST include the work title and
  author name for attribution.
- **FR-011**: Cross-text examples MUST be navigable — clicking one
  opens the referenced passage in context.
- **FR-012**: System MUST present a list of available processed works
  for the user to choose from.
- **FR-013**: All text processing and analysis MUST happen before the
  user reads, not during reading (no delays at read time).

### Key Entities

- **Work**: A literary text available for reading. Attributes: title,
  author, publication year. A work contains an ordered sequence of
  words.
- **Word**: An individual token in a work. Attributes: surface form
  (as written), base form (dictionary form), reading (furigana),
  part of speech, containing sentence.
- **Word Entry**: A unique vocabulary item identified by its base form.
  Attributes: part of speech, reading, dictionary definition,
  contextual explanation, cross-text usage examples.
- **User Vocabulary**: The user's personal record of a word entry.
  Attributes: first seen date, exposure count, last seen date,
  learning status (new / learning / known).

### Assumptions

- Single user system — no authentication or multi-user support needed.
- Only Japanese literary texts from public domain sources.
- The user has N1-level Japanese proficiency (advanced), so the tool
  focuses on literary/archaic vocabulary rather than basic words.
- Word boundaries and readings are determined during preprocessing,
  not at read time.
- The initial content set consists of 5 classic Japanese short stories.

## Clarifications

### Session 2026-02-28

- Q: MVP 是否需要支援手機/平板的觸控操作？ → A: 完整響應式支援 — 桌面版 hover + 手機版 tap，兩種不同的互動模式。
- Q: 使用者是否需要手動管理詞彙狀態？ → A: 被動為主、可手動覆寫 — 系統自動追蹤，但使用者可在 tooltip 中手動標記「已學會」或「重新學習」。
- Q: 桌面端 tooltip 關閉行為？ → A: 延遲消失 — 滑鼠可移進 tooltip 保持顯示（約 300ms 延遲），移出後消失。允許使用者操作 tooltip 內的連結和按鈕。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: User can open any processed work and begin reading
  within 2 seconds.
- **SC-002**: Tooltip appears within 100 milliseconds for previously
  looked-up words.
- **SC-003**: Verb and adjective tooltips display at least 2 cross-text
  usage examples when the word appears in 3+ processed works.
- **SC-004**: After looking up a word in one work, the word is
  automatically highlighted in all other works without any user action.
- **SC-005**: A new literary work can be made available for reading
  within 5 minutes of initiating processing.
- **SC-006**: 95% of words in the initial 5 works have accurate
  readings and appropriate explanations.

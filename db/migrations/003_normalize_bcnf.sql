-- 003_normalize_bcnf.sql
-- Normalize schema to BCNF
--
-- Changes:
--   1. NEW: sentences table (extract sentence_text from tokens)
--   2. NEW: cross_text_examples table (replace JSONB on word_entries)
--   3. tokens: remove base_form, pos, reading, pos_detail, sentence_text
--              (available via word_entry_id JOIN word_entries)
--              add sentence_id FK
--   4. word_entries: remove cross_text_examples JSONB, work_count (derived)
--
-- BCNF violations fixed:
--   - tokens.{base_form, pos, reading} determined by word_entry_id (non-superkey)
--   - tokens.sentence_text repeated across tokens in same sentence
--   - word_entries.cross_text_examples violates 1NF (non-atomic JSONB)
--   - word_entries.work_count is a derived aggregate

-- 1. Create sentences table
CREATE TABLE sentences (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    work_id uuid NOT NULL REFERENCES works(id) ON DELETE CASCADE,
    position int NOT NULL,
    text text NOT NULL,
    UNIQUE (work_id, position)
);

ALTER TABLE sentences ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read" ON sentences FOR SELECT USING (true);

-- 2. Create cross_text_examples table (replaces JSONB column)
CREATE TABLE cross_text_examples (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    word_entry_id uuid NOT NULL REFERENCES word_entries(id) ON DELETE CASCADE,
    work_id uuid NOT NULL REFERENCES works(id) ON DELETE CASCADE,
    sentence_id uuid NOT NULL REFERENCES sentences(id) ON DELETE CASCADE,
    token_position int NOT NULL,
    UNIQUE (word_entry_id, work_id, token_position)
);

CREATE INDEX cross_text_examples_word_entry_id ON cross_text_examples(word_entry_id);

ALTER TABLE cross_text_examples ENABLE ROW LEVEL SECURITY;
CREATE POLICY "allow_read" ON cross_text_examples FOR SELECT USING (true);

-- 3. Modify tokens: remove redundant columns, add sentence_id
DROP INDEX tokens_base_form_pos;

ALTER TABLE tokens DROP COLUMN base_form;
ALTER TABLE tokens DROP COLUMN pos;
ALTER TABLE tokens DROP COLUMN reading;
ALTER TABLE tokens DROP COLUMN pos_detail;
ALTER TABLE tokens DROP COLUMN sentence_text;
ALTER TABLE tokens ADD COLUMN sentence_id uuid REFERENCES sentences(id);

-- 4. Modify word_entries: remove denormalized fields
ALTER TABLE word_entries DROP COLUMN cross_text_examples;
ALTER TABLE word_entries DROP COLUMN work_count;

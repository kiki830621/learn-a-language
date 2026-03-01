-- 001_initial_schema.sql
-- Immersive Japanese Reader: Core schema

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

-- 002_record_word_lookup.sql
-- Postgres function for recording word lookups (M1)
--
-- Behavior:
--   - UPSERT into user_vocabulary
--   - On INSERT: exposure_count = 1, status = 'new'
--   - On conflict (existing record): increment exposure_count, update last_seen_at
--   - Status transitions: NULL→'new', stays 'new' until manual change
--     (automatic transitions removed; user controls learning/known status)

CREATE OR REPLACE FUNCTION record_word_lookup(p_word_entry_id uuid)
RETURNS TABLE (
    word_entry_id uuid,
    exposure_count int,
    status text
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    INSERT INTO user_vocabulary (word_entry_id, exposure_count, status)
    VALUES (p_word_entry_id, 1, 'new')
    ON CONFLICT (word_entry_id) DO UPDATE
    SET
        exposure_count = user_vocabulary.exposure_count + 1,
        last_seen_at = now()
    RETURNING
        user_vocabulary.word_entry_id,
        user_vocabulary.exposure_count,
        user_vocabulary.status;
END;
$$;

-- User profile: optional display_name (nickname) and avatar_url (stored in MinIO).
ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

-- Keep display_name in sync with username for rows that never had a custom
-- nickname, so the UI can render one without extra fallback logic.
UPDATE users SET display_name = username WHERE display_name IS NULL;

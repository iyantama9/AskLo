ALTER TABLE chats ALTER COLUMN model SET DEFAULT 'mk/haiku-4.5';

ALTER TABLE messages ADD COLUMN IF NOT EXISTS file_urls JSONB DEFAULT '[]'::jsonb;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS file_names JSONB DEFAULT '[]'::jsonb;

UPDATE messages
SET file_urls = CASE
    WHEN file_url IS NULL OR file_url = '' THEN '[]'::jsonb
    ELSE jsonb_build_array(file_url)
  END,
  file_names = CASE
    WHEN file_name IS NULL OR file_name = '' THEN '[]'::jsonb
    ELSE jsonb_build_array(file_name)
  END
WHERE file_urls = '[]'::jsonb
  AND file_names = '[]'::jsonb
  AND (file_url IS NOT NULL OR file_name IS NOT NULL);

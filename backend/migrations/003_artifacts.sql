CREATE TABLE IF NOT EXISTS artifacts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id INT REFERENCES users(id) ON DELETE CASCADE,
  chat_id INT REFERENCES chats(id) ON DELETE CASCADE,
  message_id INT REFERENCES messages(id) ON DELETE SET NULL,
  title VARCHAR(255) NOT NULL,
  kind VARCHAR(40) NOT NULL,
  files JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_artifacts_chat_id ON artifacts(chat_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_artifacts_owner_id ON artifacts(owner_id, created_at DESC);

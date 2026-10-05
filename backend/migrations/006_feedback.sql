CREATE TABLE IF NOT EXISTS feedback (
  id BIGSERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  chat_id INT REFERENCES chats(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  model VARCHAR(100),
  user_agent TEXT,
  ip INET,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT feedback_content_length CHECK (char_length(trim(content)) BETWEEN 1 AND 2000)
);

CREATE INDEX IF NOT EXISTS idx_feedback_user_created ON feedback(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_created ON feedback(created_at DESC);

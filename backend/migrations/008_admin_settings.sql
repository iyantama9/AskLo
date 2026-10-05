CREATE TABLE IF NOT EXISTS admin_settings (
  key VARCHAR(100) PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed default settings
INSERT INTO admin_settings (key, value) VALUES
  ('fallback_chat', '"mk/haiku-4.5"'),
  ('fallback_image', '"wz/flux-kontext"'),
  ('default_model', '"mk/haiku-4.5"')
ON CONFLICT (key) DO NOTHING;

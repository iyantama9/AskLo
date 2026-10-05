-- Admin Dashboard Tables

-- Models table (migrate from hardcoded array to database)
CREATE TABLE IF NOT EXISTS models (
  id VARCHAR(100) PRIMARY KEY,
  owned_by VARCHAR(100) NOT NULL,
  display_name VARCHAR(255) NOT NULL,
  supports_reasoning BOOLEAN DEFAULT false,
  supports_vision BOOLEAN DEFAULT false,
  supports_image_generation BOOLEAN DEFAULT false,
  supports_browse BOOLEAN DEFAULT false,
  cost_tier VARCHAR(50) DEFAULT 'standard',
  enabled BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Router configurations
CREATE TABLE IF NOT EXISTS router_configs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  base_url TEXT NOT NULL,
  api_key TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  timeout_ms INT DEFAULT 30000,
  max_retries INT DEFAULT 3,
  metadata JSONB DEFAULT '{}'::jsonb,
  last_tested_at TIMESTAMPTZ,
  last_test_status VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Promotions
CREATE TABLE IF NOT EXISTS promotions (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  unlimited_quota BOOLEAN DEFAULT true,
  quota_multiplier DECIMAL(10,2) DEFAULT 1.0,
  custom_limits JSONB DEFAULT '{}'::jsonb,
  is_active BOOLEAN DEFAULT true,
  created_by INT REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- User promotions (many-to-many)
CREATE TABLE IF NOT EXISTS user_promotions (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  promotion_id INT REFERENCES promotions(id) ON DELETE CASCADE,
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  assigned_by INT REFERENCES users(id),
  UNIQUE(user_id, promotion_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_models_enabled ON models(enabled);
CREATE INDEX IF NOT EXISTS idx_router_configs_active ON router_configs(is_active);
CREATE INDEX IF NOT EXISTS idx_promotions_dates ON promotions(start_date, end_date, is_active);
CREATE INDEX IF NOT EXISTS idx_user_promotions_user ON user_promotions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_promotions_promo ON user_promotions(promotion_id);

-- Seed default models (migrate from hardcoded array)
INSERT INTO models (id, owned_by, display_name, supports_reasoning, supports_vision, supports_image_generation, supports_browse, cost_tier, enabled)
VALUES
  ('mk/sonnet-4.5', 'Anthropic', 'Claude Sonnet 4.5', true, true, false, true, 'premium', true),
  ('mk/sonnet-4.5-thinking', 'Anthropic', 'Claude Sonnet 4.5', true, true, false, true, 'premium', true),
  ('mk/haiku-4.5', 'Anthropic', 'Claude Haiku 4.5', true, true, false, true, 'standard', true),
  ('mk/haiku-4.5-thinking', 'Anthropic', 'Claude Haiku 4.5', true, true, false, true, 'standard', true),
  ('dh/moonshotai/Kimi-K2.6', 'Moonshot', 'Kimi K2.6', false, true, false, true, 'standard', true),
  ('wz/kimi-k2.7-code', 'Moonshot', 'Kimi K2.7 Code', false, false, false, true, 'standard', true),
  ('qc/glm-5.2', 'Zhipu', 'GLM 5.2', false, true, false, true, 'standard', true),
  ('wz/mimo-v2.5-pro', 'Xiaomi', 'Xiaomi MiMo V2.5 Pro', false, false, false, true, 'standard', true),
  ('wz/mimo-v2.5', 'Xiaomi', 'Xiaomi MiMo V2.5', false, false, false, true, 'standard', true),
  ('wz/qwen3.6-plus', 'Alibaba', 'Qwen 3.6 Plus', false, false, false, true, 'standard', true),
  ('wz/gpt-5.6-luna', 'OpenAI', 'GPT 5.6 Luna', false, false, false, true, 'premium', true),
  ('qc/qwen-image-2.0', 'Alibaba', 'Qwen Image 2.0', false, false, true, false, 'image', true),
  ('qc/qwen-image-2.0-pro', 'Alibaba', 'Qwen Image Pro', false, false, true, false, 'image', true),
  ('qc/qwen-image-2.0-2026-03-03', 'Alibaba', 'Qwen Image 2.0 2026-03-03', false, false, true, false, 'image', true),
  ('qc/qwen-image-2.0-pro-2026-06-22', 'Alibaba', 'Qwen Image Pro 2026-06-22', false, false, true, false, 'image', true),
  ('qc/qwen-image-2.0-pro-2026-04-22', 'Alibaba', 'Qwen Image Pro 2026-04-22', false, false, true, false, 'image', true),
  ('qc/qwen-image-2.0-pro-2026-03-03', 'Alibaba', 'Qwen Image Pro 2026-03-03', false, false, true, false, 'image', true),
  ('qc/qwen-image-max', 'Alibaba', 'Qwen Image Max', false, false, true, false, 'image', true),
  ('qc/qwen-image-max-2025-12-30', 'Alibaba', 'Qwen Image Max 2025-12-30', false, false, true, false, 'image', true),
  ('qc/qwen-image-plus', 'Alibaba', 'Qwen Image Plus', false, false, true, false, 'image', true),
  ('qc/qwen-image-plus-2026-01-09', 'Alibaba', 'Qwen Image Plus 2026-01-09', false, false, true, false, 'image', true),
  ('qc/wan2.7-image-pro', 'Alibaba', 'Wan 2.7 Image Pro', false, false, true, false, 'image', true),
  ('qc/wan2.7-image', 'Alibaba', 'Wan 2.7 Image', false, false, true, false, 'image', true),
  ('qc/z-image-turbo', 'Alibaba', 'Z Image Turbo', false, false, true, false, 'image', true),
  ('qc/qwen-image-edit', 'Alibaba', 'Qwen Image Edit', false, true, true, false, 'image', true),
  ('qc/qwen-image-edit-plus', 'Alibaba', 'Qwen Image Edit Plus', false, true, true, false, 'image', true),
  ('qc/qwen-image-edit-plus-2025-12-15', 'Alibaba', 'Qwen Image Edit Plus 2025-12-15', false, true, true, false, 'image', true),
  ('qc/qwen-image-edit-plus-2025-10-30', 'Alibaba', 'Qwen Image Edit Plus 2025-10-30', false, true, true, false, 'image', true),
  ('qc/qwen-image-edit-max', 'Alibaba', 'Qwen Image Edit Max', false, true, true, false, 'image', true),
  ('qc/qwen-image-edit-max-2026-01-16', 'Alibaba', 'Qwen Image Edit Max 2026-01-16', false, true, true, false, 'image', true)
ON CONFLICT (id) DO NOTHING;

-- Seed default router config
INSERT INTO router_configs (name, base_url, api_key, is_active)
VALUES ('Default Router', 'http://localhost:8000', 'default_key', true)
ON CONFLICT (name) DO NOTHING;

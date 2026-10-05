-- Dynamic Model Catalog
-- Stores AI models that can be dynamically added/removed without code changes
CREATE TABLE IF NOT EXISTS model_catalog (
  id SERIAL PRIMARY KEY,

  -- Model identity
  model_id VARCHAR(100) UNIQUE NOT NULL,  -- e.g. "anthropic/claude-sonnet-4.5"
  provider VARCHAR(50) NOT NULL,           -- e.g. "anthropic", "openai", "google"
  display_name VARCHAR(100) NOT NULL,      -- e.g. "Claude Sonnet 4.5"

  -- Capabilities
  supports_streaming BOOLEAN DEFAULT true,
  supports_tools BOOLEAN DEFAULT true,
  supports_vision BOOLEAN DEFAULT false,
  supports_documents BOOLEAN DEFAULT false,

  -- Context and limits
  max_tokens INT DEFAULT 4096,
  context_window INT DEFAULT 200000,

  -- Pricing (per 1M tokens)
  input_price_per_1m DECIMAL(10,4) DEFAULT 0,
  output_price_per_1m DECIMAL(10,4) DEFAULT 0,

  -- UI metadata
  category VARCHAR(50) DEFAULT 'general',  -- general, vision, code, fast, etc.
  icon_emoji VARCHAR(10),
  description TEXT,

  -- Status
  is_enabled BOOLEAN DEFAULT true,
  is_featured BOOLEAN DEFAULT false,
  sort_order INT DEFAULT 0,

  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_model_catalog_enabled ON model_catalog(is_enabled, sort_order);
CREATE INDEX IF NOT EXISTS idx_model_catalog_provider ON model_catalog(provider);

-- Router Configuration
-- Stores routing rules for load balancing and failover
CREATE TABLE IF NOT EXISTS router_config (
  id SERIAL PRIMARY KEY,

  -- Rule identity
  rule_name VARCHAR(100) UNIQUE NOT NULL,
  description TEXT,

  -- Matching criteria (JSONB for flexibility)
  -- Example: {"provider": "anthropic", "tier": "fast"}
  match_criteria JSONB DEFAULT '{}'::jsonb,

  -- Target models (ordered array of model_ids for fallback)
  -- Example: ["anthropic/claude-sonnet-4.5", "anthropic/claude-opus-4"]
  target_models JSONB NOT NULL,

  -- Routing strategy
  strategy VARCHAR(50) DEFAULT 'fallback',  -- fallback, round_robin, least_latency

  -- Limits and quotas
  rate_limit_per_minute INT,
  max_retries INT DEFAULT 2,
  timeout_seconds INT DEFAULT 120,

  -- Status
  is_enabled BOOLEAN DEFAULT true,
  priority INT DEFAULT 0,

  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_router_config_enabled ON router_config(is_enabled, priority DESC);

-- Promotions
-- Stores promotional messages, banners, or announcements
CREATE TABLE IF NOT EXISTS promotions (
  id SERIAL PRIMARY KEY,

  -- Content
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  link_url TEXT,
  link_text VARCHAR(100),

  -- Targeting
  target_audience VARCHAR(50) DEFAULT 'all',  -- all, new_users, premium, etc.
  target_locations JSONB,  -- Array of page locations where this shows

  -- Visual
  promotion_type VARCHAR(50) DEFAULT 'banner',  -- banner, modal, toast, card
  color_scheme VARCHAR(50) DEFAULT 'primary',   -- primary, success, warning, info
  icon_emoji VARCHAR(10),

  -- Scheduling
  start_date TIMESTAMPTZ,
  end_date TIMESTAMPTZ,

  -- Status
  is_active BOOLEAN DEFAULT true,
  priority INT DEFAULT 0,

  -- Analytics
  view_count INT DEFAULT 0,
  click_count INT DEFAULT 0,

  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_promotions_active ON promotions(is_active, start_date, end_date);

-- 004_admin_dashboard.sql already created `promotions` without `priority`;
-- reconcile idempotently so the index below cannot fail on fresh databases.
ALTER TABLE promotions ADD COLUMN IF NOT EXISTS priority INT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_promotions_priority ON promotions(priority DESC);

-- Seed with current hardcoded models
INSERT INTO model_catalog (model_id, provider, display_name, supports_streaming, supports_tools, supports_vision, supports_documents, max_tokens, context_window, category, icon_emoji, description, is_featured, sort_order) VALUES
-- Anthropic Claude models
('anthropic/claude-sonnet-4.5', 'anthropic', 'Claude Sonnet 4.5', true, true, true, true, 8192, 200000, 'general', '🧠', 'Most capable and intelligent model', true, 1),
('anthropic/claude-opus-4', 'anthropic', 'Claude Opus 4', true, true, true, true, 4096, 200000, 'general', '👑', 'Highest quality responses', true, 2),
('anthropic/claude-haiku-4.5', 'anthropic', 'Claude Haiku 4.5', true, true, false, false, 4096, 200000, 'fast', '⚡', 'Fast and efficient', true, 3),

-- OpenAI models
('openai/gpt-4o', 'openai', 'GPT-4o', true, true, true, false, 4096, 128000, 'general', '🤖', 'OpenAI flagship model', true, 10),
('openai/gpt-4o-mini', 'openai', 'GPT-4o Mini', true, true, true, false, 4096, 128000, 'fast', '🚀', 'Affordable and fast', false, 11),
('openai/o1', 'openai', 'OpenAI o1', false, false, false, false, 4096, 200000, 'reasoning', '🧮', 'Advanced reasoning', false, 12),
('openai/o1-mini', 'openai', 'OpenAI o1 Mini', false, false, false, false, 4096, 128000, 'reasoning', '🔢', 'Fast reasoning', false, 13),

-- Google models
('google/gemini-2.0-flash-exp', 'google', 'Gemini 2.0 Flash', true, true, true, false, 8192, 1000000, 'fast', '💎', 'Lightning fast responses', true, 20),
('google/gemini-2.0-flash-thinking-exp', 'google', 'Gemini 2.0 Flash Thinking', true, true, true, false, 8192, 1000000, 'reasoning', '💭', 'Advanced thinking mode', false, 21),
('google/gemini-exp-1206', 'google', 'Gemini Exp 1206', true, true, true, false, 8192, 2000000, 'general', '🔮', 'Experimental flagship', false, 22),

-- Meta models
('meta/llama-3.3-70b', 'meta', 'Llama 3.3 70B', true, true, false, false, 4096, 128000, 'general', '🦙', 'Open source powerhouse', false, 30),

-- Qwen vision models
('qwen/qwen-2.5-vl-72b', 'qwen', 'Qwen 2.5 VL 72B', true, false, true, false, 4096, 32000, 'vision', '👁️', 'Advanced vision understanding', false, 40),
('qwen/qwen-2.5-vl-32b', 'qwen', 'Qwen 2.5 VL 32B', true, false, true, false, 4096, 32000, 'vision', '📷', 'Balanced vision model', false, 41),
('qwen/qwen-2.5-vl-7b', 'qwen', 'Qwen 2.5 VL 7B', true, false, true, false, 4096, 32000, 'vision', '🖼️', 'Fast vision model', false, 42),

-- Mistral models
('mistral/mistral-large', 'mistral', 'Mistral Large', true, true, false, false, 4096, 128000, 'general', '🌪️', 'Powerful reasoning', false, 50),
('mistral/mistral-medium', 'mistral', 'Mistral Medium', true, true, false, false, 4096, 128000, 'general', '💨', 'Balanced performance', false, 51)

ON CONFLICT (model_id) DO NOTHING;

-- Seed default router config
INSERT INTO router_config (rule_name, description, match_criteria, target_models, strategy, is_enabled, priority) VALUES
('default_fallback', 'Default fallback chain for all requests', '{"type": "default"}', '["anthropic/claude-sonnet-4.5", "anthropic/claude-opus-4", "openai/gpt-4o"]', 'fallback', true, 0),
('fast_tier', 'Fast response models for quick queries', '{"tier": "fast"}', '["anthropic/claude-haiku-4.5", "openai/gpt-4o-mini", "google/gemini-2.0-flash-exp"]', 'round_robin', true, 10),
('vision_requests', 'Models with vision capabilities', '{"capability": "vision"}', '["anthropic/claude-sonnet-4.5", "qwen/qwen-2.5-vl-72b", "openai/gpt-4o"]', 'fallback', true, 20)

ON CONFLICT (rule_name) DO NOTHING;

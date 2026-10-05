-- Seed Qwen image generation and edit models for AskCore
INSERT INTO models (id, owned_by, display_name, supports_reasoning, supports_vision, supports_image_generation, supports_browse, cost_tier, enabled)
VALUES
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
ON CONFLICT (id) DO UPDATE
SET owned_by = EXCLUDED.owned_by,
    display_name = EXCLUDED.display_name,
    supports_reasoning = EXCLUDED.supports_reasoning,
    supports_vision = EXCLUDED.supports_vision,
    supports_image_generation = EXCLUDED.supports_image_generation,
    supports_browse = EXCLUDED.supports_browse,
    cost_tier = EXCLUDED.cost_tier,
    enabled = EXCLUDED.enabled,
    updated_at = NOW();
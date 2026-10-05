-- Provider logos: admin-managed brand logo per provider (owned_by name).
-- The model catalog merges these into each model as logo_url so the picker
-- can render the real brand logo instead of just an initial.
CREATE TABLE IF NOT EXISTS provider_logos (
  provider VARCHAR(100) PRIMARY KEY,
  logo_url TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

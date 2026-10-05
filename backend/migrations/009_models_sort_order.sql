-- Add admin-controlled ordering to the models table.
-- sort_order is NULL by default (falls back to display-name order). When the
-- admin reorders models, each row gets an explicit integer; lower values come
-- first. The catalog reads display_name ASC only for rows without a sort_order.
ALTER TABLE models ADD COLUMN IF NOT EXISTS sort_order INT;

-- Index to speed up the ordered catalog read.
CREATE INDEX IF NOT EXISTS idx_models_sort_order ON models (sort_order);

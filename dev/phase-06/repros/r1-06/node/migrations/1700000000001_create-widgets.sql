-- Up Migration
CREATE TABLE widgets (id uuid PRIMARY KEY, created_at timestamptz NOT NULL DEFAULT now());
-- Down Migration
DROP TABLE widgets;

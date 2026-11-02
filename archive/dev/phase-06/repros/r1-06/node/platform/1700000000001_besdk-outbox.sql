-- Up Migration
CREATE TABLE IF NOT EXISTS besdk_outbox (id uuid PRIMARY KEY, subject text NOT NULL);
-- Down Migration
DROP TABLE IF EXISTS besdk_outbox;

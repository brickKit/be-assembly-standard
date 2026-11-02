-- Up Migration
ALTER TABLE widgets ADD COLUMN note text;
-- Down Migration
ALTER TABLE widgets DROP COLUMN note;

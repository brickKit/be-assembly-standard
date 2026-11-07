-- The barrier's member lookup as a trigger, without (f_plain) and with (f_pinned) a pinned search_path; members empty
-- (the common case: rows that are not archived), like foundations-05-data/t10/barrier-search-path/bench.sql.
DROP SCHEMA IF EXISTS bb CASCADE; CREATE SCHEMA bb; SET search_path = bb;
CREATE TABLE be_tier_unit (id uuid PRIMARY KEY, state text);
CREATE TABLE be_tier_member (unit uuid, class text, root_id text, PRIMARY KEY (class, root_id));
CREATE TABLE t (id uuid PRIMARY KEY, v int);
CREATE FUNCTION f_plain() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text; uid text; rid text := NEW.id::text;
BEGIN
  SELECT u.state, u.id::text INTO st, uid FROM be_tier_member m JOIN be_tier_unit u ON u.id = m.unit WHERE m.class = 'c' AND m.root_id = rid;
  RETURN NEW;
END $$;
CREATE FUNCTION f_pinned() RETURNS trigger LANGUAGE plpgsql SET search_path FROM CURRENT AS $$
DECLARE st text; uid text; rid text := NEW.id::text;
BEGIN
  SELECT u.state, u.id::text INTO st, uid FROM be_tier_member m JOIN be_tier_unit u ON u.id = m.unit WHERE m.class = 'c' AND m.root_id = rid;
  RETURN NEW;
END $$;

-- the barrier's cost with and without a pinned search_path: 50k inserts into a class table, the members empty
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
\timing on
CREATE TRIGGER g BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION f_plain();
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
DROP TRIGGER g ON t; CREATE TRIGGER g BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION f_pinned();
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
DROP TRIGGER g ON t; CREATE TRIGGER g BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION f_plain();
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
DROP TRIGGER g ON t; CREATE TRIGGER g BEFORE INSERT ON t FOR EACH ROW EXECUTE FUNCTION f_pinned();
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
DROP TRIGGER g ON t;
INSERT INTO t SELECT gen_random_uuid(), i FROM generate_series(1, 50000) i; TRUNCATE t;
DROP SCHEMA bb CASCADE;

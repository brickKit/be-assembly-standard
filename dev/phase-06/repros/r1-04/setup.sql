-- r1-04 setup: two members (ra/a, rb/b) and one NOINHERIT shell login role.
-- Run as superuser against a throwaway database (see run.sh).
DROP SCHEMA IF EXISTS a CASCADE;
DROP SCHEMA IF EXISTS b CASCADE;
DROP ROLE IF EXISTS shell;
DROP ROLE IF EXISTS ra;
DROP ROLE IF EXISTS rb;

CREATE ROLE ra NOLOGIN;
CREATE ROLE rb NOLOGIN;
CREATE ROLE shell LOGIN PASSWORD 'shell' NOINHERIT;
-- PG16: membership usable only through SET ROLE, privileges not inherited (P19.5)
GRANT ra TO shell WITH INHERIT FALSE, SET TRUE;
GRANT rb TO shell WITH INHERIT FALSE, SET TRUE;
GRANT CONNECT ON DATABASE r1db TO shell;

CREATE SCHEMA a AUTHORIZATION ra;
CREATE SCHEMA b AUTHORIZATION rb;

SET ROLE ra;
-- S1: same shape in both schemas, different rows
CREATE TABLE a.widget (id int PRIMARY KEY, v text NOT NULL);
INSERT INTO a.widget VALUES (1, 'from-a');
-- S2: same name, different result type (SDK version skew: payload text vs jsonb, extra column)
CREATE TABLE a.besdk_thing (id bigint PRIMARY KEY, payload text NOT NULL);
INSERT INTO a.besdk_thing VALUES (1, 'a-text');
-- S3: same name, same types for the listed columns, b has an extra column
CREATE TABLE a.besdk_same (id bigint PRIMARY KEY, payload text NOT NULL);
INSERT INTO a.besdk_same VALUES (1, 'a-same');
RESET ROLE;

SET ROLE rb;
CREATE TABLE b.widget (id int PRIMARY KEY, v text NOT NULL);
INSERT INTO b.widget VALUES (1, 'from-b');
CREATE TABLE b.besdk_thing (id bigint PRIMARY KEY, payload jsonb NOT NULL, extra int NOT NULL DEFAULT 0);
INSERT INTO b.besdk_thing VALUES (1, '{"b":"jsonb"}', 7);
CREATE TABLE b.besdk_same (id bigint PRIMARY KEY, payload text NOT NULL, extra int NOT NULL DEFAULT 0);
INSERT INTO b.besdk_same VALUES (1, 'b-same', 7);
RESET ROLE;

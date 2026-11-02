-- Input of like-copy-indexes.txt: the indexes a LIKE ... INCLUDING ALL copy of be_bus_test.be_bus_delivery gets. psql -X -At
DROP SCHEMA IF EXISTS probe_like CASCADE; CREATE SCHEMA probe_like;
CREATE TABLE probe_like.be_bus_delivery (LIKE be_bus_test.be_bus_delivery INCLUDING ALL);
SELECT indexdef FROM pg_indexes WHERE schemaname = 'probe_like' ORDER BY indexname;
DROP SCHEMA probe_like CASCADE;

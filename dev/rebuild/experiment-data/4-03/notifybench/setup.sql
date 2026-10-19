-- A message table like the bus's: an identity, a stream, a payload of about 200 bytes.
DROP TABLE IF EXISTS msg;
CREATE TABLE msg (seq bigserial PRIMARY KEY, id uuid NOT NULL UNIQUE, stream text NOT NULL, payload text NOT NULL);

LOAD 'chdb';

CREATE TABLE secrets (
    id     INT  PRIMARY KEY,
    name   TEXT NOT NULL,
    secret TEXT NOT NULL
);
INSERT INTO secrets VALUES (1, 'alice', 'hunter2'), (2, 'bob', 'letmein');

CREATE TABLE names (
    id   INT  PRIMARY KEY,
    name TEXT NOT NULL,
    who  TEXT NOT NULL DEFAULT current_user
);

-- Clean up after any previous failed run.
SET client_min_messages = error;
DROP ROLE IF EXISTS chdb_none;
DROP ROLE IF EXISTS chdb_reader;
RESET client_min_messages;
CREATE ROLE chdb_none;
CREATE ROLE chdb_reader;
GRANT SELECT (id, name) ON secrets TO chdb_reader;
GRANT INSERT (id, name) ON names TO chdb_reader;

-- Disable quiet to emit COPY numbers
\set QUIET false

-- Copy through /tmp, which the server can always read and write.
\set names_out file:///tmp/permissions.tmp/names.tsv

-- Copying a server file requires the same role membership as a Postgres COPY.
SET ROLE chdb_reader;
COPY secrets (id, name) TO :'names_out';
COPY names (id, name) FROM :'names_out';
RESET ROLE;
GRANT pg_read_server_files, pg_write_server_files TO chdb_none, chdb_reader;

-- A role without privileges cannot copy the relation.
SET ROLE chdb_none;
COPY secrets TO :'names_out';
COPY secrets FROM :'names_out';

-- Column privileges cover only the copied columns.
SET ROLE chdb_reader;
COPY secrets TO :'names_out';
COPY secrets (id, secret) TO :'names_out';
COPY secrets (id, name) TO :'names_out';

-- The worker copies as the role that ran the COPY.
COPY names (id, name) FROM :'names_out';
RESET ROLE;
SELECT * FROM names ORDER BY id;

-- COPY TO PROGRAM remains Postgres's business.
SET ROLE chdb_reader;
COPY names TO PROGRAM 'file:///bin/cat';
RESET ROLE;

-- chDB copies every row, so row-level security cannot be applied.
ALTER TABLE secrets ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_secret ON secrets FOR SELECT TO chdb_reader USING (name = current_user);
SET ROLE chdb_reader;
COPY secrets (id, name) TO :'names_out';
SET row_security = off;
COPY secrets (id, name) TO :'names_out';
RESET row_security;
RESET ROLE;

-- The owner bypasses row-level security, so exports every row.
COPY secrets TO :'names_out';
CREATE TABLE exported (LIKE secrets);
COPY exported FROM :'names_out';
SELECT * FROM exported ORDER BY id;

-- COPY FROM writes, so a read-only transaction rejects it.
BEGIN READ ONLY;
COPY names FROM :'names_out';
ROLLBACK;

-- The worker cannot see this session's temporary relations.
CREATE TEMP TABLE tmp_names (id INT, name TEXT);
COPY tmp_names TO :'names_out';

DROP TABLE secrets, names, exported;
DROP ROLE chdb_none, chdb_reader;

-- Files belong to the server user, so ignore failure to remove them.
\! rm -rf /tmp/permissions.tmp 2>/dev/null

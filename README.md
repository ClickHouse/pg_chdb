chdb Postgres Extension
=======================

[![PGXN version](https://badge.fury.io/pg/chdb.svg)](https://badge.fury.io/pg/chdb)
[![Build Status](https://github.com/ClickHouse/pg_chdb/actions/workflows/ci.yml/badge.svg)](https://github.com/ClickHouse/pg_chdb/actions/workflows/ci.yml)

Description
-----------

This library provides PostgreSQL extensions for executing [chDB] queries in
Postgres, and for copying data from external sources into a PostgreSQL table.

### chdb Extension

The `chdb` extension runs [chDB] queries. The `chdb_query()` function executes
a single query. For example, this query:

```sql
SELECT * FROM chdb_query($$
  SELECT * FROM s3('s3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv')
$$) AS (id int, months int, days int);
```

Outputs:

```
 id | months | days
----+--------+------
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
(3 rows)
```

See the [chdb documentation](doc/chdb.md) for details.

### chdb_hook Module

The `chdb_hook` module hooks into the [COPY] command to copy data to or
from an S3, GCS, Azure Blob, file, or http URL. This example loads records
from multiple CSV files on S3 in a single [COPY] command:

```sql
CREATE TABLE times (
    id     INT NOT NULL,
    months INT NOT NULL,
    days   INT NOT NULL
);

LOAD 'chdb_hook';
COPY times FROM 's3://datasets-documentation/my-test-bucket-768/{some,another}_prefix/some_file_{1..3}.csv';
```

After which the `times` table contains the records from each file it loaded:

```pgsql
# SELECT * FROM times;
 id | months | days
----+--------+------
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
  1 |      2 |    3
  3 |      2 |    1
  4 |      5 |    6
(18 rows)
```

See the [chdb_hook documentation](doc/chdb_hook.md) for details.

Dependencies
------------

The `chdb` extension requires PostgreSQL 16 or higher and the [chDB] library
v26.7.0 or greater. The simplest way to install it is via the [lib.chdb.io]
shell script:

```sh
curl -sL https://lib.chdb.io | bash
```

Installation
------------

To build chdb, just do this:

``` sh
make
make installcheck
make install
```

If you encounter an error such as:

```
"Makefile", line 8: Need an operator
```

You need to use GNU make, which may well be installed on your system as
`gmake`:

``` sh
gmake
gmake install
gmake installcheck
```

If you encounter an error such as:

```
make: pg_config: Command not found
```

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

``` sh
env PG_CONFIG=/path/to/pg_config make && make installcheck && make install
```

If you encounter an error such as:

```
chdb_helper.c:22:10: fatal error: 'chdb.h' file not found
```

You either need to install [chDB] or tell the compiler where to find it. If,
for example, you installed it via the [lib.chdb.io] shell script, point to
`/usr/local`:

``` sh
make CFLAGS=-I/usr/local/include \
     LDFLAGS=-L/usr/local/lib
```

If you encounter an error such as:

```
ERROR:  must be owner of database regression
```

You need to run the test suite using a super user, such as the default
"postgres" super user:

``` sh
make installcheck PGUSER=postgres
```

To install the extension in a custom prefix on PostgreSQL 18 or later, pass
the `prefix` argument to `install` (but no other `make` targets):

```sh
make install prefix=/usr/local/extras
```

Then ensure that the prefix is included in the following [`postgresql.conf`
parameters]:

```ini
extension_control_path = '/usr/local/extras/postgresql/share:$system'
dynamic_library_path   = '/usr/local/extras/postgresql/lib:$libdir'
```

Author
------

*   [David E. Wheeler](https://justatheory.com/)
*   [serprex](https://github.com/serprex)

Copyright
---------

Copyright (c) 2026, ClickHouse

  [chDB]: https://clickhouse.com/chdb
    "chDB - fast, reliable, and scalable in-process database"
  [COPY]: https://www.postgresql.org/docs/current/sql-copy.html "Postgres Docs: COPY"
  [lib.chdb.io]: https://lib.chdb.io "curl -sL https://lib.chdb.io | bash"
  [`postgresql.conf` parameters]: https://www.postgresql.org/docs/devel/runtime-config-client.html#RUNTIME-CONFIG-CLIENT-OTHER

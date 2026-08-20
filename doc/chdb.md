chdb 0.0.1
===========

## Synopsis

``` psql
# CREATE EXTENSION chdb;
CREATE EXTENSION

# SELECT * FROM chdb_query('version()') AS (version text);
 version
----------
 26.5.1.1
(1 row)
```

## Description

The `chdb` extension runs [chDB] queries in a helper process.

## Functions

### `pgchdb_version`

```sql
SELECT pgchdb_version();
```

Returns the current [semantic version][semver] of the chdb extension library.
While the chdb extension version uses only the `x.y` part of the version, the
library provides the full `x.y.z` [semantic version][semver]. This value will
be the same as that returned by the Postgres 18 and later
`pg_get_loaded_modules()` function:

```sql
SELECT version
  FROM pg_get_loaded_modules()
 WHERE module_name = 'chdb';
```

### `chdb_query`

```sql
SELECT * FROM chdb_query('SELECT version()') AS (version text);
```

Executes a [chDB] query return its rows as a relation. Each call creates a
temporary chDB database on disk and deletes it once the query completes. As a
result, no objects created by previous `chdb_query()` calls, such as DDL,
persist to subsequent calls.

A column definition list (`AS (col type, ...)`) is required: PostgreSQL
requires the row structure definition before fetching rows, and that structure
must match the columns the query returns. Values are converted from chDB to
the declared types.

No role has `EXECUTE` access by default; `GRANT` to a role to allow it to use
the function.

```sql
GRANT EXECUTE ON FUNCTION chdb_query(text) TO chdb_admin;
```

**Example:**

```sql
SELECT * FROM chdb_query(
    'SELECT number AS n, number * number FROM numbers(5) ORDER BY n'
) AS (n int2, p int);
```

Output:

```
 n | p
---+----
 0 |  0
 1 |  1
 2 |  4
 3 |  9
 4 | 16
(5 rows)
```

## Versioning Policy

The chdb extension adheres to [Semantic Versioning][semver] for its public
releases.

*   The major version increments for API changes
*   The minor version increments for backward compatible SQL changes
*   The patch version increments for binary-only changes

Once installed, PostgreSQL tracks two variations of the version:

*   The library version (defined by `PG_MODULE_MAGIC` on PostgreSQL 18 and
    higher) includes the full semantic version, visible in the output of the
    `pgchdb_version()` function or the Postgres [`pg_get_loaded_modules()`]
    function.
*   The extension version (defined in the control file) includes only the
    major and minor versions, visible in the `pg_catalog.pg_extension` table,
    the output of the `pg_available_extension_versions()` function, and `\dx
    pg_clickhouse`.

In practice this means that a release that increments the patch version, e.g.
from `v0.1.0` to `v0.1.1`, benefits all databases that have loaded `v0.1` and
do not need to run `ALTER EXTENSION` to benefit from the upgrade.

A release that increments the minor or major versions, on the other hand, will
be accompanied by SQL upgrade scripts, and all existing database that contain
the extension must run `ALTER EXTENSION pg_clickhouse UPDATE` to benefit from
the upgrade.

## Authors

*   [David E. Wheeler](https://justatheory.com/)
*   [serprex](https://github.com/serprex)

## Copyright

Copyright (c) 2026, ClickHouse

  [chDB]: https://clickhouse.com/chdb
    "chDB - fast, reliable, and scalable in-process database"
  [semver]: https://semver.org/spec/v2.0.0.html "Semantic Versioning 2.0.0"

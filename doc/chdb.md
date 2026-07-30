chdb 0.0.1
===========

## Synopsis

``` psql
# CREATE EXTENSION chdb;
CREATE EXTENSION

# LOAD 'chdb';
LOAD
```

## Description

This library contains a single PostgreSQL extension, `chdb`, which provides a
background worker to execute [chDB] queries. It currently only supports [COPY]
to a URL.

## Loading

Load the chdb extension in one of the following ways as a super user. Use
whichever makes the most sense for your use case:

*   Explicitly via the [LOAD] command:

    ```sql
    LOAD 'chdb';
    ```

*   Implicitly by calling [pgchdb_version()]:

    ```sql
    SELECT pgchdb_version();
    ```

*   For all sessions, via the [session_preload_libraries] setting, via `postgresql.conf`:

    ```ini
    session_preload_libraries = chdb
    ```

    Or via [ALTER SYSTEM]:

    ```sql
    ALTER SYSTEM SET configuration_parameter = 'chdb';
    ```

    This setting can also be set on a per-database basis via [ALTER DATABASE]:

    ```sql
    ALTER DATABASE name SET configuration_parameter = 'chdb';
    ```

    Or for specific users and groups via [ALTER ROLE]:

    ```sql
    ALTER ROLE name SET configuration_parameter = 'chdb';
    ```

*   At server start via the [shared_preload_libraries] setting, so it's always
    available to all sessions and databases:

    ```ini
    shared_preload_libraries = chdb
    ```

> [!WARNING]
> Be aware that loading the chdb extension allows users to `COPY` data to and
> from files on the Postgres server, as well as to cloud storage.

## COPY Overloading

On [loading](#loading), the chdb extension library wires itself into the
Postgres [COPY] command to allow copying data `TO` or `FROM` all of the [data
formats provided by chDB][formats], and stored in local files, [AWS S3]
buckets, [Google Cloud Storage], and more. To load a table from a CSV file in
S3, for example, create the table then call `COPY` with an `s3://` URL:

```sql
CREATE TABLE times (
    id    INT PRIMARY KEY,
    months INT NOT NULL,
    days   INT NOT NULL
);

COPY times FROM 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv';
```

### Privileges

A chdb `COPY` requires the same privileges as the [COPY] it replaces: `SELECT`
on the relation or on every copied column for `COPY TO`, and `INSERT` for `COPY
FROM`. A `file://` URL reads or writes a file on the server, so also requires
membership in `pg_read_server_files` or `pg_write_server_files`. `COPY FROM`
requires a read-write transaction.

The chdb extension rejects two cases it cannot copy faithfully:

*   Relations with [row-level security] policies that apply to the copying
    role. Postgres applies such policies by rewriting `COPY TO` into a query,
    which the chdb extension does not support.
*   Temporary relations, which only the session that created them can read.

### URL Schemes

The chdb extension only executes for URL `COPY` targets that use one of the
following schemes:

| Schemes                        | Target                               | chDB Function          |
| ------------------------------ | ------------------------------------ | ---------------------- |
| `file`                         | Absolute path on the Postgres server | [`file()`]             |
| `http`, `https`                | HTTP URL                             | [`url()`]              |
| `s3`                           | [AWS S3]                             | [`s3()`]               |
| `gs`, `gcs`, `oss`             | [Google Cloud Storage]               | [`gcs()`]              |
| `az`, `azure`, `abfss`, `abfs` | [Azure Blob Storage] or [Azure ABFS] | [`azureBlobStorage()`] |
| `hdfs`                         | [Hadoop Distributed File System]     | [`hdfs()`]             |

### URL Formats

The format of URLs varies by the target.

#### File

Must be an absolute path on the Postgres server. A relative path results in an
error. The Postgres server user must have read or write access to the file, as
appropriate. For `COPY TO`, if the path does not exist, the chdb extension
will create any missing parent directories; it must have file system
permission to do so. Example:

```
file:///tmp/users.parquet
```

#### HTTP

Any normal HTTP URL, including in public cloud storage. For `COPY TO`, the
chdb extension will attempt to `POST` the data to the URL. Example:

```
https://datasets-documentation.s3.eu-west-3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv
```

#### S3

S3 URLs take this form:

```
s3://{bucket}/{path}
```

GCS URLs take this form:

#### GCS

```
gcs://storage.googleapis.com/{bucket}/{path}
```

#### Azure Blob Storage

Use a `blob.windows.net` URL with an account name as the subdomain:

```
az://{account}.blob.core.windows.net/{container}/{blob}
```

Or use some other host name:

```
az://{host}/{container}/{blob}
```

#### Azure ABFS

Must use this format:

```
abfs://{container}@{account}.dfs.core.windows.net/{blob}
```

### Path Wildcards

URL Paths may contain globs in `COPY FROM` commands. Files must match the
whole path pattern, not only the suffix or prefix. There is one exception that
if the path refers to an existing directory and does not use globs, a `*` will
be implicitly added to the path so all the files in the directory are
selected.

*   `*`: Arbitrarily match many characters except `/`, including the empty string.
*   `?`: Match an arbitrary single character.
*   `{some_string,another_string,yet_another_one}`: Substitute any of strings
    "some_string", "another_string", and "yet_another_one". The strings may
    contain `/`.
*   `{N..M}`: Match any number `>= N` and `<= M`.
*   `**`: Recursively match all files in a directory.

For example, to load data from these files in a single command:

*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_1.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_2.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_3.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/some_prefix/some_file_4.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/another_prefix/some_file_1.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/another_prefix/some_file_2.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/another_prefix/some_file_3.csv
*   https://clickhouse-public-datasets.s3.amazonaws.com/my-test-bucket-768/another_prefix/some_file_4.csv

Use `{some,another}_prefix` to match the two directory names and
`some_file_{1..3}.csv'` to match the files, like so:

```sql
CREATE TABLE times (
    id     INT NOT NULL,
    months INT NOT NULL,
    days   INT NOT NULL
);

COPY times FROM 's3://datasets-documentation/my-test-bucket-768/{some,another}_prefix/some_file_{1..3}.csv';
```

### Options

The chdb `COPY` command supports the following options:

#### `format`:

The format to read or write. Must be one of the [formats] provided by
[chDB], which include TSV, CSV, Parquet, Iceberg, JSON, and more. Omit or
set to `auto` to have chDB determine the format from file name extension
at the end of the URL.

#### `structure`

The [chDB] data structure to use for the data. Consists of a list of column
names and [ClickHouse data types] and modifiers. If omitted, the chdb
extension maps the Postgres data types to generally-appropriate ClickHouse
types; see [Data Types](#data-types) for details. If set to `auto`, chDB
attempts to infer the types.

Example:

```sql
COPY users TO 'file:///tmp/users.parquet' (
    structure 'id Int64, name String, age UInt8, attributes JSON'
);
```

#### `access_key` and `access_secret`

Long-term credentials for the AWS account user to authenticate requests.
Supported by S3, GCS, Azure, and HDFS URLs.

#### `session_token`

Session token to use with the `access_key` and `access_secret`. Supported
by S3 URLs.

#### `compression`

File compression format. Use if the compression cannot be inferred from
the file name. Supported values:

*   `auto` (default)
*   `none`
*   `gzip` or `gz`
*   `brotli` or `br`
*   `xz` or `LZMA`
*   `zstd` or `zst`

#### `timeout`

Request timeout in milliseconds. Applies to HTTP, S3, GCS, and Azure URLs.
Defaults to `30000` (30s).

### Data Types

In the absence of an explicit [structure](#structure) option, the chDB
extension automatically maps Postgres types to reasonable chDB equivalents.
When they don't match your use case, specify the [structure](#structure) to
get the types you need.

| Postgres    | chDB          | Notes                                                                  |
| ----------- | ------------- | ---------------------------------------------------------------------- |
| boolean     | Bool          |                                                                        |
| name        | String        |                                                                        |
| text        | String        |                                                                        |
| inet        | String        | Override with `IPv4` or `IPv6` if data contains only one or the other. |
| cidr        | String        |                                                                        |
| macaddr     | String        |                                                                        |
| macaddr8    | String        |                                                                        |
| interval    | String        |                                                                        |
| tsvector    | String        |                                                                        |
| tsquery     | String        |                                                                        |
| jsonpath    | String        |                                                                        |
| money       | String        |                                                                        |
| circle      | String        |                                                                        |
| enum        | String        |                                                                        |
| line        | String        |                                                                        |
| varchar     | String        |                                                                        |
| varbit      | String        |                                                                        |
| char        | FixedString   |                                                                        |
| bit         | FixedString   |                                                                        |
| bpchar      | String        |                                                                        |
| int2        | Int16         |                                                                        |
| int4        | Int32         |                                                                        |
| int8        | Int64         |                                                                        |
| oid         | UInt32        |                                                                        |
| oid8        | UInt64        |                                                                        |
| json        | String        | Override with `JSON` if data contains only objects.                    |
| jsonb       | String        | Override with `JSON` if data contains only objects.                    |
| point       | String        |                                                                        |
| lseg        | String        |                                                                        |
| path        | String        |                                                                        |
| box         | String        |                                                                        |
| polygon     | String        |                                                                        |
| float4      | Float32       |                                                                        |
| float8      | Float64       |                                                                        |
| date        | Date32        |                                                                        |
| time        | Time64(6)     | Override with `String` for formats that don't support dates.           |
| timetz      | String        |                                                                        |
| timestamp   | DateTime64(6) |                                                                        |
| timestamptz | DateTime64(6) |                                                                        |
| numeric     | Decimal       |                                                                        |
| uuid        | UUID          |                                                                        |

## Versioning Policy

The chdb extension adheres to [Semantic Versioning] for its public releases.

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

## Author

[David E. Wheeler](https://justatheory.com/)

## Copyright

Copyright (c) 2026, ClickHouse

  [chDB]: https://clickhouse.com/chdb
    "chDB - fast, reliable, and scalable in-process database"
  [Semantic Versioning]: https://semver.org/spec/v2.0.0.html "Semantic Versioning 2.0.0"
  [COPY]: https://www.postgresql.org/docs/current/sql-copy.html "Postgres Docs: COPY"
  [formats]: https://github.com/chdb-io/chdb/blob/main/refs/clickhouse-formats-settings.md#complete-format-names-table
    "chDB Docs: Complete Format Names Table"
  [row-level security]: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
    "Postgres Docs: Row Security Policies"
  [LOAD]: https://www.postgresql.org/docs/current/sql-load.html "Postgres Docs: LOAD"
  [session_preload_libraries]:https://www.postgresql.org/docs/18/runtime-config-client.html#GUC-SESSION-PRELOAD-LIBRARIES
    "Postgres Docs: `session_preload_libraries`"
  [shared_preload_libraries]:https://www.postgresql.org/docs/18/runtime-config-client.html#GUC-SESSION-PRELOAD-LIBRARIES
    "Postgres Docs: `shared_preload_libraries`"
  [ALTER SYSTEM]: https://www.postgresql.org/docs/18/sql-altersystem.html "Postgres Docs: ALTER SYSTEM"
  [ALTER DATABASE]: https://www.postgresql.org/docs/current/sql-alterdatabase.html "Postgres Docs: ALTER DATABASE"
  [ALTER ROLE]: https://www.postgresql.org/docs/18/sql-alterrole.html "Postgres Docs: ALTER ROLE"
  [AWS S3]: https://aws.amazon.com/s3/ "Cloud Object Storage - Amazon S3 - Amazon Web Services"
  [Google Cloud Storage]: https://cloud.google.com/storage "Cloud Storage - Google Cloud"
  [`file()`]: https://clickhouse.com/docs/sql-reference/table-functions/file
    "ClickHouse Docs: file Table Function"
  [`url()`]: https://clickhouse.com/docs/sql-reference/table-functions/url
    "ClickHouse Docs: url Table Function"
  [`s3()`]: https://clickhouse.com/docs/sql-reference/table-functions/s3
    "ClickHouse Docs: s3 Table Function"
  [`gcs()`]: https://clickhouse.com/docs/sql-reference/table-functions/gcs
    "ClickHouse Docs: gcs Table Function"
  [Azure Blob Storage]: https://azure.microsoft.com/en-us/products/storage/blobs/
  [Azure ABFS]: https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction-abfs-uri
    "Use the Azure Data Lake Storage URI (ABFS) - Azure Storage"
  [`azureBlobStorage()`]: https://clickhouse.com/docs/sql-reference/table-functions/azureBlobStorage
    "ClickHouse Docs: azureBlobStorage Table Function"
  [Hadoop Distributed File System]: https://en.wikipedia.org/wiki/Apache_Hadoop#Overview
    "Wikipedia: Apache Hadoop Overview"
  [`hdfs()`]: https://clickhouse.com/docs/sql-reference/table-functions/hdfs
    "ClickHouse Docs: hdfs Table Function"
  [ClickHouse data types]: https://clickhouse.com/docs/reference/data-types/index
    "ClickHouse Docs: Data Types in ClickHouse"

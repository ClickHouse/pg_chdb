chdb 0.0.1
===========

## Synopsis

``` psql
# CREATE EXTENSION chdb;
CREATE EXTENSION

# LOAD 'chdb';
LOAD

# CREATE TABLE times (
    id     INT NOT NULL,
    months INT NOT NULL,
    days   INT NOT NULL
);
CREATE TABLE

# COPY times FROM 's3://datasets-documentation/my-test-bucket-768/{some,another}_prefix/some_file_{1..3}.csv';
COPY 16
```

## Description

This library contains a single PostgreSQL extension, `chdb`, which provides a
background worker to execute [chDB] queries. It currently only supports [COPY]
to or from a URL.

## Loading

Load the chdb extension in one of the following ways as a super user. Use
whichever makes the most sense for your use case:

*   Explicitly via the [LOAD] command; lasts for the duration of a session:

    ```sql
    LOAD 'chdb';
    ```

*   Implicitly by calling [pgchdb_version()]; lasts for the duration of a session:

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
> Be aware that loading the chdb extension allows users in the
> `pg_read_server_files` or `pg_write_server_files` roles to `COPY` data to
> and from files on the Postgres server, as well as cloud storage.

## COPY Overloading

On [loading](#loading), the chdb extension library wires itself into the
Postgres [COPY] command to copy data `TO` or `FROM` any of the supported [data
formats provided by chDB][formats] in local files, [AWS S3] buckets, [Google
Cloud Storage], and more. To load a table from a CSV file in S3, for example,
create the table then call `COPY` with an `s3://` URL:

```sql
CREATE TABLE times (
    id     INT PRIMARY KEY,
    months INT NOT NULL,
    days   INT NOT NULL
);

COPY times FROM 's3://datasets-documentation/my-test-bucket-768/some_prefix/some_file_1.csv';
```

### Background Worker

When the chdb extension library detects a `COPY` command it can handle, it
starts a [background worker] to do so. The background worker keeps the
resource consumption of [chDB] separate from the main Postgres process, an
advantage for an occasionally-used workflow such as loading data from a data
lake.

As a consequence, execution may fail if the Postgres server has too many
background workers loaded already. In that situation, the `COPY` will fail
with this error:

```
ERROR:  out of background worker slots
```

To solve this problem, increase the [max_worker_processes] setting to allow
more background workers and restart the service:

```sql
ALTER SYSTEM SET max_worker_processes = 12;
```

### Privileges

A chdb `COPY` requires the same privileges as the [COPY] it replaces: `SELECT`
on the relation or on every copied column for `COPY TO`, and `INSERT` for
`COPY FROM`. A `file://` URL reads or writes a file on the server, so also
requires membership in `pg_read_server_files` or `pg_write_server_files`.
`COPY FROM` requires a read-write transaction.

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
error. The Postgres user must be a member of the `pg_read_server_files` or
`pg_write_server_files` role, as appropriate. The Postgres system user must
have read or write access to the file, as appropriate. For `COPY TO`, if the
path does not exist, the chdb extension will create any missing parent
directories; it must have file system permission to do so. Example:

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

S3 URLs may take the form of an S3 URI

```
s3://{bucket}/{path}
```

Or of an object URL:

```
s3://{bucket}.{region}.amazonaws.com/{path}
```

#### GCS

GCS URLs take the form of a public URL:

```
gs://storage.googleapis.com/{bucket}/{path}
```

Or a Cloud Storage URI, which chdb converts to a public URL:

```
gs://{bucket}/{path}
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

ABFS URLs must use this format:

```
abfs://{container}@{account}.dfs.core.windows.net/{blob}
```

#### HDFS URLS

HDFS URLs may use typical HTTP-style URLs with an optional port:

```
hdfs://{host}/{path}
hdfs://{host}:{port}/{path}
```

### Path Wildcards

URL Paths may contain globs in `COPY FROM` commands. Files must match the
whole path pattern, not only the suffix or prefix. The one exception: when
path refers to an existing directory and does not use globs, a `*` will be
implicitly added to the path to select all of the files in the directory.

The supported wildcards:

*   `*`: Arbitrarily match many characters except `/`, including the empty string.
*   `?`: Match an arbitrary single character.
*   `{groucho,harpo,chico}`: Substitute any of strings "groucho", "harpo", and
    "chico". The strings may contain `/`.
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

The [chDB] data structure for a row. Consists of a list of column names and
[ClickHouse data types] and modifiers. If omitted, the chdb extension maps the
Postgres data types to generally-appropriate ClickHouse types; see [Data
Types](#data-types) for details. If set to `auto`, chDB attempts to infer the
types.

Example:

```sql
COPY users TO 'file:///tmp/users.parquet' (
    structure 'id Int64, name String, age Nullable(UInt8), attributes JSON'
);
```

#### `access_key` and `access_secret`

Long-term credentials for the AWS account user to authenticate requests.

*   **S3:** An AWS [access key ID and access secret], often defined with the
    environment variables `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
*   **GCS:** A GCP [HMAC key and secret]
*   **Azure:** An Azure Storage account name and [access key]

#### `session_token`

AWS session token to use with the `access_key` and `access_secret`, often
defined by the environment variable `AWS_SESSION_TOKEN`. Used only for S3
URLs.

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
override the generated types with those you need.

| Postgres    | chDB                                     | Notes                                                                  |
| ----------- | ---------------------------------------- | ---------------------------------------------------------------------- |
| boolean     | Bool                                     |                                                                        |
| name        | String                                   |                                                                        |
| text        | String                                   |                                                                        |
| inet        | String                                   | Override with `IPv4` or `IPv6` if data contains only one or the other. |
| cidr        | String                                   |                                                                        |
| macaddr     | String                                   |                                                                        |
| macaddr8    | String                                   |                                                                        |
| interval    | String                                   |                                                                        |
| tsvector    | String                                   |                                                                        |
| tsquery     | String                                   |                                                                        |
| jsonpath    | String                                   |                                                                        |
| money       | String                                   |                                                                        |
| enum        | String                                   |                                                                        |
| varchar     | String                                   |                                                                        |
| varbit      | String                                   |                                                                        |
| char        | FixedString                              |                                                                        |
| bit         | FixedString                              |                                                                        |
| bpchar      | String                                   |                                                                        |
| int2        | Int16                                    |                                                                        |
| int4        | Int32                                    |                                                                        |
| int8        | Int64                                    |                                                                        |
| oid         | UInt32                                   |                                                                        |
| oid8        | UInt64                                   |                                                                        |
| json        | String                                   | Override with `JSON` if data contains only objects.                    |
| jsonb       | String                                   | Override with `JSON` if data contains only objects.                    |
| float4      | Float32                                  |                                                                        |
| float8      | Float64                                  |                                                                        |
| date        | Date32                                   |                                                                        |
| time        | Time64(6)                                | Override with `String` for formats that don't support times.           |
| timetz      | String                                   |                                                                        |
| timestamp   | DateTime64(6)                            | Declared with the `UTC` time zone; values cross as UTC instants.       |
| timestamptz | DateTime64(6)                            | Declared with the `UTC` time zone; values cross as UTC instants.       |
| numeric     | Decimal                                  |                                                                        |
| uuid        | UUID                                     |                                                                        |
| point       | `Point`                                  | Same two coordinates as Postgres.                                      |
| lseg        | `LineString`                             | A line of exactly two points.                                          |
| path        | `LineString`                             | A closed path repeats its first point.                                 |
| polygon     | `Ring`                                   | A ring closes implicitly, as a polygon does.                           |
| box         | `Tuple(high Point, low Point)`           | The two corners, sorted as Postgres sorts.                             |
| circle      | `Tuple(center Point, radius Float64)`    |                                                                        |
| line        | `Tuple(a Float64, b Float64, c Float64)` | The equation `Ax + By + C = 0`.                                        |

Array types map to `Array`s of the mapped element type. ClickHouse constrains
nullability per column while Postgres constrains it per array, so elements are
always `Nullable`.

### Limitations

Due to a few known issues and variations in the behaviors of data types
between Postgres and chDB, the chdb extension `COPY` support has the following
limitations:

*   Cannot `COPY` relations with [row-level security] policies that apply to
    the copying role. Postgres applies such policies by rewriting `COPY TO`
    into a query, which the chdb extension does not support.
*   Cannot `COPY` temporary relations, which only the session that created
    them can read.
*   ClickHouse has no NULL array, so `COPY TO` stores an empty array (`[]`)
    for a `NULL`.
*   ClickHouse represents the equivalents of `lseg`, `path`, or `polygon` as
    arrays; thus NULL values of these types also `COPY TO` an empty array
    (`[]`).
*   NULL values output for a specified [structure](#structure) that doesn't
    define the column as Nullable will be output as their default values.
    Always explicitly define nullable columns in the [structure](#structure)
    to avoid this conversion.
*   An open `path` whose last point equals its first outputs as a closed path.
*   Protobuf has no null in a repeated field, so it omits NULL values in
    arrays.
*   The chDB [JSON type] supports only JSON objects; override the default
    `String` mapping for `json` and `jsonb` with `JSON` only if all values are
    JSON object. (ClickHouse/ClickHouse#68428)
*   The chDB [JSON type] ignores `null`s; object keys with NULL values will be
    omitted on output. Override the default `String` mapping for `json` and
    `jsonb` with `JSON` only if object values aren't `null` or their loss is
    acceptable. (ClickHouse/ClickHouse#68428)
*   The JSON, JSONCompact, and JSONColumnsWithMetadata formats always validate
    UTF-8, so they emit bytea values with replacement characters.
*   `COPY FROM` reads a Protobuf `Nullable` field containing an empty string
    or zero as `NULL`. (chdb-io/chdb-core#152)
*   `COPY TO` Parquet drops `NULL`s from a Nullable Tuple's own null map.
    (ClickHouse/ClickHouse#112427)
*   The Parquet, Arrow, ArrowStream, ORC, Avro, Protobuf, ProtobufList,
    MsgPack and BSONEachRow formats have no type corresponding to Postgres
    `time` or chDB `Time64`. Configure `time` columns as `String`s in an
    explicit [structure](#structure) to preserve their values.
*   Protobuf output truncates timestamp values to the second.
*   Protobuf output does not support dates prior to 1970-01-01. Configure
    `time` columns as `String`s in an explicit [structure](#structure) to
    preserve their values. (ClickHouse/ClickHouse#111860)
*   The ORC format incorrectly writes out dates after 2059-09-18 due to an
    integer overflow. Override dates with the `String` type to avoid this
    issue.
*   The ORC format raises an error on `timestamp` values from 2262 and later.
    Will be fixed when [chDB] upgrades to ClickHouse v26.7 or greater.
    (ClickHouse/ClickHouse#109295)

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
  [access key ID and access secret]: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html
    "AWS Identity and Access Management: Manage access keys for IAM users"
  [HMAC key and secret]: https://docs.cloud.google.com/storage/docs/authentication/hmackeys
    "Google Cloud Storage: HMAC keys"
  [access key]: https://learn.microsoft.com/en-us/azure/storage/common/storage-account-keys-manage?tabs=azure-cli
    "Azure: Manage storage account access keys"
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
  [background worker]: https://www.postgresql.org/docs/current/bgworker.html
    "Postgres Docs: Background Worker Processes"
  [max_worker_processes]: https://www.postgresql.org/docs/current/runtime-config-resource.html#GUC-MAX-WORKER-PROCESSES
    "Postgres Docs: max_worker_processes"
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

# Changelog

All notable changes to this project will be documented in this file. It uses the
[Keep a Changelog] format, and this project adheres to [Semantic Versioning].

  [Keep a Changelog]: https://keepachangelog.com/en/1.1.0/
  [Semantic Versioning]: https://semver.org/spec/v2.0.0.html
    "Semantic Versioning 2.0.0"

## [v0.1.1] — Unreleased

### ⚡ Improvements

*   Support mapping `BFloat16` to Postgres `real`, and `Interval` types to
    Postgres `interval` ([#76]).
*   Added PostgreSQL 15 support.
*   Map `UInt64`, `Int128`, `Int256`, `UInt128`, and `UInt256` to Postgres
    `numeric`, so values above the `bigint` range no longer raise an error.
    A derived column carries the precision spanning its chDB type ([#78]).

### 🐞 Bug Fixes

*   `DateTime64` or `Time64` now defaults to millisecond precision ([#76]).
*   Added the `date_time_output_format='iso'` setting to each chDB query to
    always format `timestamp` and `timestamptz` values in plain text formats
    with the ISO-8601 format in UTC, converting `timestamp` values from the
    current `timezone` setting.

### 💅🏻 Quality

*   Added comprehensive tests for timestamp and timestamptz `COPY` output and
    round-tripping, including the impact of the `timezone` setting on
    `timestamp` values.

### 📚 Documentation

*   Added the "Timestamp Conversion" section to the [chdb_hook docs] to
    document the ISO-8601 format of plain text exports of `timestamp` and
    `timestamptz` values, as well as the impact of the `timezone` setting on
    exported and imported values.

  [v0.1.1]: https://github.com/clickhouse/pg_chdb/compare/v0.1.0...v0.1.1
  [#76]: https://github.com/clickhouse/pg_chdb/issues/76
  [#78]: https://github.com/clickhouse/pg_chdb/pulls/78
  [chdb_hook docs]: ./doc/chdb_hook.md
  [structure]: ./doc/chdb_hook.md#structure "chdb_hook Docs: structure"

## [v0.1.0] — 2026-08-25

The theme of this release is *Shakedown.*

### ⚡ Improvements

*   New extension, everything fresh!
*   Relies on a helper app, `chdb_helper`, to encapsulate all interaction with
    [chDB]
*   chdb extension provides `chdb_query()` to execute a single, stateless
    query.
*   chdb_hooks module hooks into the `COPY` command to copy data from a remote
    URL in any of the [formats] supported by chDB
*   chdb_hooks also hooks into the `CREATE TABLE` command to copy and or
    define the column structure for the table from a remote URL in any of the
    [formats] supported by chDB
*   The `COPY` and `CREATE TABLE` hooks support a variety of URL schemes,
    including:
    *   `file`
    *   `http` and `https`
    *   `s3` for [AWS S3]
    *   `gs` for [Google Cloud Storage]
    *   `az` for [Azure Blob Storage]
    *   `abfs` for [Azure ABFS]
*   Data type mapping provided by the [pg-clickhouse-c] header-only library

### 🏗️ Build Setup

*   Requires [chDB] v26.7.0
*   PGXS build pipeline
*   PGXN and GitHub release workflows
*   Limited to macOS and Linux (only platforms supported by [chDB])
*   Dynamic linking to [chDB] by default
*   Statically link [chDB] with `LIBCHDB_BUILD=static`
*   Automatically download [chDB] with `BUNDLE_LIBCHDB=1`

### 📚 Documentation

*   chdb extension reference documentation in [doc/chdb.md](doc/chdb.md)
*   chdb_hook module reference documentation in [doc/chdb_hook.md](doc/chdb_hook.md)

  [v0.1.0]: https://github.com/clickhouse/pg_chdb/compare/fca4dc1...v0.1.0
  [chDB]: https://clickhouse.com/chdb "chDB - fast, reliable, and scalable in-process database"
  [formats]: https://github.com/chdb-io/chdb/blob/main/refs/clickhouse-formats-settings.md#complete-format-names-table
    "chDB Docs: Complete Format Names Table"
  [AWS S3]: https://aws.amazon.com/s3/ "Cloud Object Storage - Amazon S3 - Amazon Web Services"
  [Google Cloud Storage]: https://cloud.google.com/storage "Cloud Storage - Google Cloud"
  [Azure Blob Storage]: https://azure.microsoft.com/en-us/products/storage/blobs/
  [Azure ABFS]: https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction-abfs-uri
    "Use the Azure Data Lake Storage URI (ABFS) - Azure Storage"
  [pg-clickhouse-c]: https://github.com/ClickHouse/pg-clickhouse-c/
    "Turn a ClickHouse Native block into PostgreSQL `Datum`s and back."

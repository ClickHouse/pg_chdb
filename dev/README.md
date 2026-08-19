# pg_chdb Development Tools

This directory contains scripts and configurations to assist with the
development of the chdb extensions.

*   `bear.json`: [Bear Configuration](#bear-configuration)
*   `bear.yml`: [Bear Configuration](#bear-configuration)
*   `README.md`: This file
*   `type_table.awk`: [Data Type Table](#data-type-table)

## Data Type Table

`type_table.awk` rewrites the inferred data type table in
[doc/chdb_hook.md](../doc/chdb_hook.md) from the table that pg-clickhouse-c
generates out of its own regression test:

```sh
make type-table
```

pg-clickhouse-c maps a chDB type to a Postgres type in `pgch_pg_type_for`,
which reports pseudo types for Map and Tuple that no Postgres column holds, so
the filter swaps in the `text` declarations that `CREATE TABLE` writes instead,
and renames the header columns to `chDB` and `Postgres`. Validated by `make
lint`.

## Bear Configuration

Configuration files for [Bear], used to generate the `compile_commands.json`
file:

```sh
make compile_commands.json
```

This file is used by the `clang-tidy` and `lint` targets to analyze the
chdb extensions source code to report issues. The pg_chdb project enables all
warnings and converts them to errors, but this configuration gives
`clang-tidy` indigestion. We use the Bear configuration to disable all errors
to avoid this issue.

There are currently two files:

*   `bear.yml` works with Bear 4 and later, the current release
*   `bear.json` works with Bear 3, which ships with Debian

The `compile_commands.json` target determines which to use.

  [Bear]: https://github.com/rizsotto/Bear "Bear generates a compilation database for Clang tooling"

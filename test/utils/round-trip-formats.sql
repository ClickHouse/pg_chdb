\set ECHO errors
-- This file `COPY`s data from :from_table to a file, then `COPY`s from that
-- file to :to_table, then compares the two tables to ensure their contents
-- are identical by running an `EXCEPT` query that returns zero rows. It runs
-- this round-trip for every supported format that supports both input and
-- output, listed here:
--
-- https://github.com/chdb-io/chdb/blob/main/refs/clickhouse-formats-settings.md#complete-format-names-table)

\set test_url file:///tmp/ :output_file
\pset tuples_only on
\pset format unaligned
\pset fieldsep ': '

\if :{?columns}
\else
\set columns *
\endif

COPY :"from_table" TO :'test_url' (format 'TabSeparated');
COPY :"to_table" FROM :'test_url' (format 'TabSeparated');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TabSeparated' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TabSeparatedRaw');
COPY :"to_table" FROM :'test_url' (format 'TabSeparatedRaw');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TabSeparatedRaw' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TabSeparatedWithNames');
COPY :"to_table" FROM :'test_url' (format 'TabSeparatedWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TabSeparatedWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TabSeparatedWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'TabSeparatedWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TabSeparatedWithNamesAndTypes' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TabSeparatedRawWithNames');
COPY :"to_table" FROM :'test_url' (format 'TabSeparatedRawWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TabSeparatedRawWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TabSeparatedRawWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'TabSeparatedRawWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TabSeparatedRawWithNamesAndTypes' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CSV');
COPY :"to_table" FROM :'test_url' (format 'CSV');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CSV' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CSVWithNames');
COPY :"to_table" FROM :'test_url' (format 'CSVWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CSVWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CSVWithNames');
COPY :"to_table" FROM :'test_url' (format 'CSVWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CSVWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CSVWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'CSVWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CSVWithNamesAndTypes' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CustomSeparated');
COPY :"to_table" FROM :'test_url' (format 'CustomSeparated');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CustomSeparated' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CustomSeparatedWithNames');
COPY :"to_table" FROM :'test_url' (format 'CustomSeparatedWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CustomSeparatedWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CustomSeparatedWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'CustomSeparatedWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CustomSeparatedWithNamesAndTypes' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Values');
COPY :"to_table" FROM :'test_url' (format 'Values');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Values' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSON');
COPY :"to_table" FROM :'test_url' (format 'JSON');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSON' FROM x;

/* ERROR: Format JSONStrings is not suitable for input
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONStrings');
COPY :"to_table" FROM :'test_url' (format 'JSONStrings');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONStrings' FROM x;
*/

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONColumns');
COPY :"to_table" FROM :'test_url' (format 'JSONColumns');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONColumns' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONColumnsWithMetadata');
COPY :"to_table" FROM :'test_url' (format 'JSONColumnsWithMetadata');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONColumnsWithMetadata' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompact');
COPY :"to_table" FROM :'test_url' (format 'JSONCompact');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompact' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactColumns');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactColumns');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactColumns' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONEachRow');
COPY :"to_table" FROM :'test_url' (format 'JSONEachRow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONEachRow' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONStringsEachRow');
COPY :"to_table" FROM :'test_url' (format 'JSONStringsEachRow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONStringsEachRow' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactEachRow');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactEachRow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactEachRow' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactStringsEachRow');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactStringsEachRow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactStringsEachRow' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactEachRowWithNames');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactEachRowWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactEachRowWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactEachRowWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactEachRowWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactEachRowWithNamesAndTypes' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactStringsEachRowWithNames');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactStringsEachRowWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactStringsEachRowWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONCompactStringsEachRowWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'JSONCompactStringsEachRowWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONCompactStringsEachRowWithNamesAndTypes' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'JSONObjectEachRow');
COPY :"to_table" FROM :'test_url' (format 'JSONObjectEachRow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'JSONObjectEachRow' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TSKV');
COPY :"to_table" FROM :'test_url' (format 'TSKV');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TSKV' FROM x;

/* ERROR: The format Template requires a schema
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Template');
COPY :"to_table" FROM :'test_url' (format 'Template');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Template' FROM x;
*/

/* ERROR: The format Template requires a schema
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'TemplateIgnoreSpaces');
COPY :"to_table" FROM :'test_url' (format 'TemplateIgnoreSpaces');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'TemTemplateIgnoreSpacesplate' FROM x;
*/

/* ERROR: This input format is only suitable for tables with a single column of type String
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'LineAsString');
COPY :"to_table" FROM :'test_url' (format 'LineAsString');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'LineAsString' FROM x;
*/

/* This input format is only suitable for tables with a single column of type String
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'RawBLOB');
COPY :"to_table" FROM :'test_url' (format 'RawBLOB');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'RawBLOB' FROM x;
*/

/* ERROR: There is no INSERT queries in MySQL dump file
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'MySQLDump');
COPY :"to_table" FROM :'test_url' (format 'MySQLDump');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'MySQLDump' FROM x;
*/

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Native');
COPY :"to_table" FROM :'test_url' (format 'Native');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Native' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'RowBinary');
COPY :"to_table" FROM :'test_url' (format 'RowBinary');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'RowBinary' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'RowBinaryWithNames');
COPY :"to_table" FROM :'test_url' (format 'RowBinaryWithNames');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'RowBinaryWithNames' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'RowBinaryWithNamesAndTypes');
COPY :"to_table" FROM :'test_url' (format 'RowBinaryWithNamesAndTypes');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'RowBinaryWithNamesAndTypes' FROM x;

/* ERROR: Failed to receive table structure
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'RowBinaryWithDefaults');
COPY :"to_table" FROM :'test_url' (format 'RowBinaryWithDefaults');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'RowBinaryWithDefaults' FROM x;
*/

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Parquet');
COPY :"to_table" FROM :'test_url' (format 'Parquet');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Parquet' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Arrow');
COPY :"to_table" FROM :'test_url' (format 'Arrow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Arrow' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'ArrowStream');
COPY :"to_table" FROM :'test_url' (format 'ArrowStream');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'ArrowStream' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'ORC');
COPY :"to_table" FROM :'test_url' (format 'ORC');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'ORC' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Avro');
COPY :"to_table" FROM :'test_url' (format 'Avro');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Avro' FROM x;

/* ERROR: Empty Schema Registry URL
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'AvroConfluent');
COPY :"to_table" FROM :'test_url' (format 'AvroConfluent');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'AvroConfluent' FROM x;
*/

/* Round-trip fails for some types. :-( */
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Protobuf');
COPY :"to_table" FROM :'test_url' (format 'Protobuf');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Protobuf' FROM x;

/* ERROR: The ProtobufSingle format can't be used to write multiple rows because this format doesn't have any row delimiter
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'ProtobufSingle');
COPY :"to_table" FROM :'test_url' (format 'ProtobufSingle');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'ProtobufSingle' FROM x;
*/

/* Round-trip fails for some types. :-( */
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'ProtobufList');
COPY :"to_table" FROM :'test_url' (format 'ProtobufList');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'ProtobufList' FROM x;

/* ERROR: Unknown format CapnProto
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'CapnProto');
COPY :"to_table" FROM :'test_url' (format 'CapnProto');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'CapnProto' FROM x;
*/

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'MsgPack');
COPY :"to_table" FROM :'test_url' (format 'MsgPack');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'MsgPack' FROM x;

TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'BSONEachRow');
COPY :"to_table" FROM :'test_url' (format 'BSONEachRow');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'BSONEachRow' FROM x;

/* ERROR: Unexpected number of columns for Npy input format
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'Npy');
COPY :"to_table" FROM :'test_url' (format 'Npy');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'Npy' FROM x;
*/

/* ERROR: Unknown format DWARF
TRUNCATE :"to_table";
COPY :"from_table" TO :'test_url' (format 'DWARF');
COPY :"to_table" FROM :'test_url' (format 'DWARF');
WITH x AS (
    SELECT :columns FROM :"from_table" EXCEPT ALL SELECT :columns FROM :"to_table"
) SELECT COUNT(*) = 0, 'DWARF' FROM x;
*/

\pset fieldsep '|'
\pset format aligned
\pset tuples_only off
\set ECHO all

#!/usr/bin/awk -f
# Filter pg-clickhouse-c type tables into doc/chdb_hook.md.
# pgch_pg_type_for reports pseudo types no column holds; CREATE TABLE uses text.
# COPY uses default type options but not upstream's encoder
#
# usage: (cd vendor/pg-clickhouse-c && ./gen_type_table.awk [-v section=ENCODE]) |
#            dev/type_table.awk [-v section=ENCODE] [markdown-file]

function die(msg) {
    print "type_table: " msg > "/dev/stderr"
    exit (failed = 1)
}

function joined(c, out) {
    out = $2
    for (c = 2; c <= COLS; c++) out = out "|" $(c + 1)
    return out
}

function read_row(got) {
    got = (getline < "/dev/stdin")
    if (got < 0) die("cannot read standard input")
    if (got == 0) return 0
    if ($0 !~ /^\|/) die("expected a table row, got: " $0)
    if (NF != COLS + 2) die("row of " (NF - 2) " cells among rows of " COLS)
    return 1
}

function keep_row(r, c, text) {
    for (c = 1; c <= COLS; c++) {
        cell[r, c] = text = $(c + 1)
        if (length(text) > width[c]) width[c] = length(text)
    }
}

function center(text, c) {
    return sprintf("%" int((width[c] + length(text)) / 2) "s", text)
}

function row(r, c, text, out) {
    out = "|"
    for (c = 1; c <= COLS; c++) {
        text = (r == 0) ? center(cell[r, c], c) : cell[r, c]
        out = out " " sprintf("%-" width[c] "s", text) " |"
    }
    return out
}

function rule(c, dashes, out) {
    out = "|"
    for (c = 1; c <= COLS; c++) {
        dashes = sprintf("%" (width[c] + 2) "s", "")
        gsub(/ /, "-", dashes)
        out = out dashes "|"
    }
    return out
}

BEGIN {
    FS = " *\\| *"
    if (section == "") section = "TYPE"
    begin = section "-TABLE-BEGIN"
    end = section "-TABLE-END"

    if (section == "TYPE") {
        COLS = 4
        header = "ClickHouse|Default PostgreSQL|Additional read targets|Notes"
    } else if (section == "ENCODE") {
        COLS = 3
        header = "PostgreSQL|Default ClickHouse|Notes"
    } else {
        die("unknown section " section)
    }

    note["numeric"] = "Also when precision exceeds 76 digits."
    note["numeric(12,6)"] = "Precision and scale carry over."
    note["inet"] = "Override with `IPv4` or `IPv6` if data contains only one or the other."
    note["interval"] = "Override with an `Interval` unit such as `IntervalDay`."
    note["json"] = "Override with `JSON` if data contains only objects."
    note["jsonb"] = "Override with `JSON` if data contains only objects."
    note["time"] = "Override with `String` for formats that don't support times."
    note["timestamp"] = "Converted from session time zone."
    note["point"] = "Same two coordinates as Postgres."
    note["lseg"] = "A line of exactly two points."
    note["path"] = "A closed path repeats its first point."
    note["polygon"] = "A ring closes implicitly, as a polygon does."
    note["box"] = "The two corners, sorted as Postgres sorts."
    note["line"] = "The equation `Ax + By + C = 0`."

    upstream["Map(K,V)"] = "record[]|One record per pair"
    ours["Map(K,V)"] = "text[][]|One row of text items per pair"
    upstream["Nested(...)"] = "record[]|One record per nested row"
    ours["Nested(...)"] = "text[][]|One row of text items per nested row"
    upstream["Tuple(...)"] = "record|Match field order and types"
    ours["Tuple(...)"] = "text[]|Fields become text items"

    if (!read_row()) die("no table on standard input")
    if (joined() != header) die("header <" joined() "> is not <" header ">")

    sub(/(Default )?ClickHouse/, "chDB")
    keep_row(0)
    if (!read_row() || $2 !~ /^-+$/) die("no rule under the header")

    while (read_row()) {
        type = $2
        seen[type] = 1
        if (section == "ENCODE") {
            $4 = note[type]
        } else if (type in ours) {
            if ($3 "|" $5 != upstream[type]) {
                die("swap for " type " expects <" upstream[type] ">, " \
                    "got <" $3 "|" $5 ">")
            }
            split(ours[type], swap, "|")
            $3 = swap[1]
            $5 = swap[2]
        }
        if (section == "TYPE" && $3 ~ /^record(\[\])*$/) {
            die("no swap for pseudo type row " type)
        }
        keep_row(++rows)
    }
    for (type in ours) {
        if (section == "TYPE" && !(type in seen)) die("no row for " type)
    }
    for (type in note) {
        if (section == "ENCODE" && !(type in seen)) die("no row for " type)
    }

    table = row(0) "\n" rule()
    for (r = 1; r <= rows; r++) table = table "\n" row(r)

    target = ARGV[1]
    if (target == "") {
        print table
        exit
    }
}

index($0, begin) { doc = doc $0 "\n" table "\n"; spliced = 1; skip = 1; next }
index($0, end) { skip = 0 }
!skip { doc = doc $0 "\n" }

END {
    if (failed) exit 1
    if (target == "") exit
    if (!spliced || skip) die(target " marks no table to replace")

    printf "%s", doc > target
    close(target)
    print "type_table: " target " updated" > "/dev/stderr"
}

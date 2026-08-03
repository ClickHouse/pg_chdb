#ifndef CHDB_NATIVE_H
#define CHDB_NATIVE_H

#include "chdb.h"
#include "postgres.h"

#include "utils/relcache.h"

/* Copy and clean up a chDB error, truncating it if necessary. */
extern char*
chdb_capture_error(const char* error);

/*
 * Scans the `attnums` columns of `rel` into `stream` as Native blocks carrying
 * the columns `structure` declares, which is what ClickHouse matches them
 * against. Returns the rows sent.
 */
extern uint64_t
chdb_native_send(
    Relation rel,
    const char* structure,
    List* attnums,
    chdb_insert_stream stream
);

/*
 * Inserts the rows `result` streams as Native blocks into the `attnums` columns
 * of `rel`, other columns taking their default. Returns the rows inserted, not
 * counting any a BEFORE trigger suppressed.
 */
extern uint64_t
chdb_native_receive(
    Relation rel,
    List* attnums,
    chdb_connection conn,
    chdb_result* result
);

#endif /* CHDB_NATIVE_H */

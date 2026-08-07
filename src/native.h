#ifndef CHDB_NATIVE_H
#define CHDB_NATIVE_H

#include "postgres.h"

#include "nodes/pg_list.h"
#include "utils/relcache.h"

#include "helper.h"

/*
 * Scans the `attnums` columns of `rel` into `helper` as Native blocks carrying
 * the columns `structure` declares, which is what ClickHouse matches them
 * against. Returns the rows sent.
 */
extern uint64_t
chdb_native_send(
    Relation rel,
    const char* structure,
    List* attnums,
    chdbHelper* helper
);

/*
 * Inserts the rows `helper` streams as Native blocks into the `attnums` columns
 * of `rel`, other columns taking their default. Runs under `rtable`, the range
 * table the caller has already checked. Returns the rows inserted, not counting
 * any a BEFORE trigger suppressed.
 */
extern uint64_t
chdb_native_receive(
    Relation rel,
    List* attnums,
    List* rtable,
    List* rteperminfos,
    chdbHelper* helper
);

#endif /* CHDB_NATIVE_H */

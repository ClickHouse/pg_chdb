#ifndef CHDB_HELPER_H
#define CHDB_HELPER_H

#include "postgres.h"

/*
 * The chdb_helper process answering one COPY. The two sides meet on fixed
 * descriptors:
 *
 *   fd 0   Native blocks in, COPY TO
 *   fd 1   Native blocks out, COPY FROM
 *   fd 2   error text
 *   fd 3   setup payload, closed once written
 *   exit   0 on success, CHDB_HELPER_LOST_BACKEND when the channel broke and
 *          there was nobody left to tell, else nonzero with fd 2 saying why
 *
 * Row counts never cross: the Postgres side counts what it scanned or stored.
 */
typedef struct chdbHelper chdbHelper;

/*
 * Starts the helper on `query`, bound to `nparams` named parameters. The helper
 * dies with the backend.
 */
extern chdbHelper*
chdb_helper_start(
    bool is_from,
    const char* query,
    char* const* names,
    char* const* values,
    size_t nparams
);

/* pgch_chunk_source next_chunk over the helper's Native output. */
extern bool
chdb_helper_read(void* helper, const void** p, size_t* n, char** error);

/* Sends one Native block, raising if the helper has gone. */
extern void
chdb_helper_write(chdbHelper* helper, const void* p, size_t len);

/* Ends the stream and waits for the helper, raising unless it exited cleanly. */
extern void
chdb_helper_finish(chdbHelper* helper);

#endif /* CHDB_HELPER_H */

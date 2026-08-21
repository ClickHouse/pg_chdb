#ifndef CHDB_HELPER_H
#define CHDB_HELPER_H

#include "postgres.h"
#include "setup.h"

/*
 * The chdb_helper process answering one COPY. The two sides meet on fixed
 * descriptors:
 *
 *   fd 0   Native blocks in, INSERT, COPY TO
 *   fd 1   Native blocks out, SELECT, COPY FROM
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
    chdbHelperContext* ctx,
    const char* query,
    char* const* names,
    char* const* values,
    size_t nparams
);

/*
 * Reads up to `len` bytes of Native output into `buf`. Returns number of bytes
 * read, or zero at end of stream. Reports helper failures as errors.
 */
extern size_t
chdb_helper_recv(chdbHelper* helper, void* buf, size_t len);

/* Sends one Native block, raising if the helper has gone. */
extern void
chdb_helper_write(chdbHelper* helper, const void* p, size_t len);

/* Ends the stream and waits for the helper, raising unless it exited cleanly. */
extern void
chdb_helper_finish(chdbHelper* helper);

#endif /* CHDB_HELPER_H */

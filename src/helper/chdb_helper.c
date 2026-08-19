/*
 * Runs one COPY's chDB query and exits.
 *
 * This is the only program in the distribution that links libchdb. It holds no
 * Postgres state and the postmaster does not know it exists, so libchdb may
 * abort or segfault on an allocation failure without costing more than the COPY
 * that provoked it. See src/helper.c.
 *
 * Reads the setup payload from CHDB_SETUP_FD, then streams Native blocks: out
 * on stdout for COPY FROM, in on stdin for COPY TO. Anything to say goes to
 * stderr, and a nonzero exit tells the backend to raise.
 */

#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "chdb.h"

#include "../setup.h"

/* Native is the only format either direction crosses in. */
static const char native_format[] = "Native";

/* Native bytes moved in one read or write. */
#define CHDB_HELPER_IO_BYTES (256 * 1024)

static void
fail(const char* what) {
    fprintf(stderr, "%s\n", what);
    exit(1);
}

static void*
not_null(void* p) {
    if (!p) {
        fail("chdb: out of memory");
    }

    return p;
}

/* The whole setup payload, which the backend closes once it has written it. */
static char*
read_setup(size_t* len) {
    size_t cap = 64 * 1024;
    size_t got = 0;
    char* buf  = not_null(malloc(cap));

    for (;;) {
        if (got == cap) {
            cap *= 2;
            if (cap > CHDB_SETUP_MAX) {
                fail("chdb: setup payload is too large");
            }
            buf = not_null(realloc(buf, cap));
        }
        ssize_t n = read(CHDB_SETUP_FD, buf + got, cap - got);
        if (n > 0) {
            got += (size_t)n;
        } else if (n == 0) {
            break;
        } else if (errno != EINTR) {
            fail("chdb: could not read the setup payload");
        }
    }
    *len = got;

    return buf;
}

typedef struct cursor {
    const char* at;
    const char* end;
} cursor;

static uint8_t
take1(cursor* c) {
    if (c->at == c->end) {
        fail("chdb: setup payload is truncated");
    }

    return (uint8_t)*c->at++;
}

static uint16_t
take2(cursor* c) {
    if ((size_t)(c->end - c->at) < sizeof(uint16_t)) {
        fail("chdb: setup payload is truncated");
    }
    uint16_t val;
    memcpy(&val, c->at, sizeof(val));
    c->at += sizeof(val);

    return val;
}

/* Borrowed from the setup payload, which the process holds to the end. */
typedef struct str {
    const char* data;
    size_t len;
} str;

static str
take_str(cursor* c) {
    if ((size_t)(c->end - c->at) < sizeof(uint32_t)) {
        fail("chdb: setup payload is truncated");
    }
    uint32_t len;
    memcpy(&len, c->at, sizeof(len));
    c->at += sizeof(len);

    if ((size_t)(c->end - c->at) < len) {
        fail("chdb: setup payload is truncated");
    }
    str val = { c->at, len };
    c->at += len;

    return val;
}

/* Parameters as the _n entry points take them, all of it borrowed. */
typedef struct params {
    const char** names;
    const size_t* name_lens;
    const char** values;
    const size_t* value_lens;
    size_t count;
} params;

/* False once the backend has gone, which is not ours to report. */
static bool
write_all(const char* at, size_t len) {
    while (len) {
        ssize_t put = write(STDOUT_FILENO, at, len);

        if (put > 0) {
            at += put;
            len -= (size_t)put;
        } else if (errno != EINTR) {
            return false;
        }
    }

    return true;
}

/* COPY FROM: the query's Native blocks, straight out to the backend. */
static int
run_select(chdb_connection conn, str query, const params* par) {
    chdb_result* stream = chdb_stream_query_with_params_n(
        conn,
        query.data,
        query.len,
        native_format,
        sizeof(native_format) - 1,
        par->names,
        par->name_lens,
        par->values,
        par->value_lens,
        par->count
    );
    const char* error = chdb_result_error(stream);
    int status        = 0;

    if (error) {
        fprintf(stderr, "%s\n", error);
        chdb_destroy_query_result(stream);

        return 1;
    }

    for (;;) {
        chdb_result* chunk      = chdb_stream_fetch_result(conn, stream);
        const char* chunk_error = chdb_result_error(chunk);

        if (chunk_error) {
            fprintf(stderr, "%s\n", chunk_error);
            status = 1;
        } else {
            size_t len = chdb_result_length(chunk);

            if (len) {
                if (write_all(chdb_result_buffer(chunk), len)) {
                    chdb_destroy_query_result(chunk);
                    continue;
                }
                status = CHDB_HELPER_LOST_BACKEND;
            }
        }
        chdb_destroy_query_result(chunk);
        break; /* end of stream, or an error either side of it */
    }

    if (status) {
        chdb_stream_cancel_query(conn, stream);
    }
    chdb_destroy_query_result(stream);

    return status;
}

/* COPY TO: the backend's Native blocks, straight into the insert. */
static int
run_insert(chdb_connection conn, str query, const params* par) {
    chdb_insert_stream stream = chdb_stream_insert_with_params_n(
        conn,
        query.data,
        query.len,
        native_format,
        sizeof(native_format) - 1,
        par->names,
        par->name_lens,
        par->values,
        par->value_lens,
        par->count
    );
    const char* error = chdb_stream_insert_error(stream);

    if (error) {
        fprintf(stderr, "%s\n", error);
        chdb_destroy_insert_stream(stream);

        return 1;
    }

    char* buf = not_null(malloc(CHDB_HELPER_IO_BYTES));
    for (;;) {
        ssize_t got = read(STDIN_FILENO, buf, CHDB_HELPER_IO_BYTES);

        if (got == 0) {
            break; /* the backend has sent every block */
        }
        if (got < 0) {
            if (errno == EINTR) {
                continue;
            }
            chdb_stream_cancel_insert(stream);
            chdb_destroy_insert_stream(stream);

            return CHDB_HELPER_LOST_BACKEND;
        }

        /* Appending blocks while the engine is behind, which is the throttle. */
        if (chdb_stream_append(stream, buf, (size_t)got) != CHDBSuccess) {
            error = chdb_stream_insert_error(stream);
            fprintf(stderr, "%s\n", error ? error : "chdb: append failed");
            chdb_stream_cancel_insert(stream);
            chdb_destroy_insert_stream(stream);

            return 1;
        }
    }

    chdb_result* done = chdb_stream_done(stream);
    error             = chdb_result_error(done);
    if (error) {
        fprintf(stderr, "%s\n", error);
    }
    chdb_destroy_query_result(done);
    chdb_destroy_insert_stream(stream);

    return error ? 1 : 0;
}

int
main(void) {
    size_t len;
    char* setup          = read_setup(&len);
    cursor cur           = { setup, setup + len };
    chdbCmdType cmd_type = take1(&cur);
    str query            = take_str(&cur);
    uint16_t npar        = take2(&cur);

    size_t nalloc       = npar ? npar : 1;
    const char** names  = not_null(calloc(nalloc, sizeof(*names)));
    size_t* name_lens   = not_null(calloc(nalloc, sizeof(*name_lens)));
    const char** values = not_null(calloc(nalloc, sizeof(*values)));
    size_t* value_lens  = not_null(calloc(nalloc, sizeof(*value_lens)));
    for (uint16_t i = 0; i < npar; i++) {
        str name  = take_str(&cur);
        str value = take_str(&cur);

        names[i]      = name.data;
        name_lens[i]  = name.len;
        values[i]     = value.data;
        value_lens[i] = value.len;
    }
    params par = { names, name_lens, values, value_lens, npar };

    /*
     * chDB's own handlers would unwind on a fatal signal, and the unwinder is
     * one of the things that fails when memory runs out. Leave the default
     * disposition so the backend sees a plain signal death.
     */
    chdb_set_signal_handlers_enabled(0);
    chdb_connection* conn = chdb_connect(1, (char*[]){ "chdb" });
    if (!conn) {
        fail("chdb: unable to connect to chDB");
    }

    int status = cmd_type == CHDB_CMD_SELECT ? run_select(*conn, query, &par)
                                             : run_insert(*conn, query, &par);

    fflush(stderr);
    chdb_close_conn(conn);

    return status;
}

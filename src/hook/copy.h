#ifndef CHDB_COPY_H
#define CHDB_COPY_H

#include "postgres.h"

#include "nodes/pg_list.h"
#include "utils/relcache.h"

#include "../setup.h"

/* URL schemes that the COPY hook understands. */
typedef enum scheme {
    http_scheme,
    s3_scheme,
    gcs_scheme,
    az_scheme,
    abfs_scheme,
    file_scheme,
    hdfs_scheme,
    no_scheme, /* Must be last.*/
} scheme;

/*
 * Contextual data from a COPY command assembled by hook.c and read into copy.c.
 */
typedef struct chdbCopyContext {
    Relation rel;
    List* attnums; /* the columns the COPY lists, all of them by default */
    /* The one-entry range table the hook checked, which the insert reuses. */
    List* rtable;
    List* rteperminfos;
    scheme scheme;
    chdbCmdType cmd_type;
    uint32_t timeout;     /* request timeout in milliseconds */
    uint16_t max_memory;  /* max_memory_usage in MB, 0 for auto */
    uint16_t max_threads; /* max_threads, 0 for auto */
    uint16_t max_parsers; /* max_parsing_threads, 0 for auto */
    /* Table function options; keep in sync with CHDB_MAX_TABLEFUNC_ARGS. */
    char* url;
    char* access_key;
    char* access_secret;
    char* session_token;
    char* format;
    char* structure;
    char* compression;
} chdbCopyContext;

/*
 * Number of table function options in chdbCopyContext +2 for Azure URL
 * parsing.
 */
#define CHDB_MAX_TABLEFUNC_ARGS 9

/*
 * Runs `ctx`'s copy through a chDB helper, in the calling transaction. Returns
 * the rows that crossed, and raises rather than returning on any failure.
 */
extern uint64_t
chdb_copy(chdbCopyContext* ctx);

#endif /* CHDB_COPY_H */

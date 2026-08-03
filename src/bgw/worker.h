#ifndef CHDB_WORKER_H
#define CHDB_WORKER_H

#if PG_VERSION_NUM >= 170000
#include "libpq/protocol.h"
#else
#include "storage/backendid.h"
typedef BackendId ProcNumber;
#define PqMsg_Terminate 'X'
#define PqMsg_ErrorResponse 'E'
#define PqMsg_NoticeResponse 'N'
#define PqMsg_Progress 'P'
#endif

/* Identifier for shared memory segments used by this extension. */
#define CHDB_SHM_MAGIC 0x49af4fb3

/*
 * We don't want to waste a lot of memory on an error queue which, most of the
 * time, will process only a handful of small messages. However, it is
 * desirable to make it large enough that a typical ClickHouse error can be
 * sent without blocking. That way, a worker that errors out can write the
 * whole message into the queue and terminate without waiting for the user
 * backend.
 */
#define CHDB_ERROR_QUEUE_SIZE 16384

/* Magic numbers for chDB state sharing .*/
#define CHDB_KEY_URL UINT64CONST(0xB000000000000001)
#define CHDB_KEY_ACCESS_KEY UINT64CONST(0xB000000000000002)
#define CHDB_KEY_ACCESS_SECRET UINT64CONST(0xB000000000000003)
#define CHDB_KEY_SESSION_TOKEN UINT64CONST(0xB000000000000004)
#define CHDB_KEY_FORMAT UINT64CONST(0xB000000000000005)
#define CHDB_KEY_STRUCTURE UINT64CONST(0xB000000000000006)
#define CHDB_KEY_COMPRESSION UINT64CONST(0xB000000000000007)
#define CHDB_KEY_HEADERS UINT64CONST(0xB000000000000008)
#define CHDB_KEY_EXTRA_CREDS UINT64CONST(0xB000000000000009)
#define CHDB_KEY_ERROR_QUEUE UINT64CONST(0xB00000000000000a)
#define CHDB_KEY_ATTLIST UINT64CONST(0xB00000000000000b)
#define CHDB_NUM_SHM_KEYS 11 /* Must equal highest CHDB_KEY number above. */

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
 * The names of the ClickHouse functions that correspond to each supported URL
 * scheme.
 */
static char const* const table_function[] = {
    [http_scheme] = "url",
    [s3_scheme]   = "s3",
    [gcs_scheme]  = "gcs", /* Alias of s3, but keep it explicit.*/
    [az_scheme]   = "azureBlobStorage",
    [abfs_scheme] = "azureBlobStorage",
    [file_scheme] = "file",
    [hdfs_scheme] = "hdfs",
};

/*
 * Strings for the URL schemes that the COPY hook understands. Same as for the
 * schemes used for dispatch in the ClickHouse 26.7 `url()` function. Must
 * allocate one more than the longest list, so that each ends in a NULL.
 * https://clickhouse.com/docs/sql-reference/table-functions/url#scheme-dispatch
 */
static char const* const scheme_name[no_scheme][4] = {
    [http_scheme] = { "http", "https" },
    [s3_scheme]   = { "s3" },
    [gcs_scheme]  = { "gs", "gcs", "oss" },
    [az_scheme]   = { "az", "azure" },
    [abfs_scheme] = { "abfs", "abfss" },
    [file_scheme] = { "file" },
    [hdfs_scheme] = { "hdfs" },
};

/*
 * Fixed-size context data for chdbCopyContext. Must not exceed BGW_EXTRALEN.
 * An assertion in hook.c ensures as much.
 */
typedef struct chdbCopyExtra {
    Oid rel_id;
    Oid db_id;
    Oid role_id;
    Oid user_id;
    int sec_context;
    scheme scheme;
    bool is_from;
    uint32_t timeout; /* request timeout in milliseconds */
    pid_t parent_pid;
    ProcNumber parent_proc_num;
} chdbCopyExtra;

/*
 * Contextual data from a COPY command assembled by hook.c and read into
 * bgw/worker.c.
 */
typedef struct chdbCopyContext {
    chdbCopyExtra extra;
    char* attlist;
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
 * Number of table function arguments in chdbCopyContext +2 for Azure URL
 * parsing.
 */
#define CHDB_MAX_TABLEFUNC_ARGS 9

#endif /* CHDB_WORKER_H */

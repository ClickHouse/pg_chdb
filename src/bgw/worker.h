#ifndef CHDB_WORKER_H
#define CHDB_WORKER_H

#if PG_VERSION_NUM >= 170000
#include "libpq/protocol.h"
#else
#define PqMsg_Terminate 'X'
#define PqMsg_ErrorResponse 'E'
#define PqMsg_NoticeResponse 'N'
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
#define CHDB_KEY_SCHEMA UINT64CONST(0xB000000000000001)
#define CHDB_KEY_TABLE UINT64CONST(0xB000000000000002)
#define CHDB_KEY_URL UINT64CONST(0xB000000000000003)
#define CHDB_KEY_ACCESS_KEY UINT64CONST(0xB000000000000004)
#define CHDB_KEY_ACCESS_SECRET UINT64CONST(0xB000000000000005)
#define CHDB_KEY_SESSION_TOKEN UINT64CONST(0xB000000000000006)
#define CHDB_KEY_FORMAT UINT64CONST(0xB000000000000007)
#define CHDB_KEY_STRUCTURE UINT64CONST(0xB000000000000008)
#define CHDB_KEY_COMPRESSION UINT64CONST(0xB000000000000009)
#define CHDB_KEY_HEADERS UINT64CONST(0xB00000000000000a)
#define CHDB_KEY_EXTRA_CREDENTIALS UINT64CONST(0xB00000000000000b)
#define CHDB_KEY_ERROR_QUEUE UINT64CONST(0xB00000000000000c)
#define CHDB_NUM_SHM_KEYS 12 /* Must equal highest CHDB_KEY number above. */

typedef enum scheme {
    http_scheme,
    https_scheme,
    s3_scheme,
    gcs_scheme,
    abs_scheme,
    no_scheme, /* Must be last.*/
} scheme;

static char const* const table_function[5] = {
    [http_scheme]  = "url",
    [https_scheme] = "url",
    [s3_scheme]    = "s3",
    [gcs_scheme]   = "gcs",
    [abs_scheme]   = "azureBlobStorage",
};

static char const* const scheme_name[5] = {
    [http_scheme] = "http", [https_scheme] = "https", [s3_scheme] = "s3",
    [gcs_scheme] = "gcs",   [abs_scheme] = "abs",
};

typedef struct chdbCopyContext {
    Oid db_id;
    Oid role_id;
    scheme scheme;
    bool is_from;
    char* schema;
    char* table;
    char* url;
    char* access_key;
    char* access_secret;
    char* session_token;
    char* format;
    char* structure;
    char* compression;
    char* headers;
    char* extra_credentials;
} chdbCopyContext;

#endif /* CHDB_WORKER_H */

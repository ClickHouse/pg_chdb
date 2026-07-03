
#ifndef CHDB_WORKER_H
#define CHDB_WORKER_H

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
    Oid dboid;
    Oid roleoid;
    scheme scheme;
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

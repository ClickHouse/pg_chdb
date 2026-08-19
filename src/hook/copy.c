/*
 * Turning a COPY into a chDB query and running it through a helper process.
 */

#include <math.h>

#include "postgres.h"

#include "miscadmin.h"
#include "utils/builtins.h"
#include "utils/guc.h"
#include "utils/rel.h"

/* PGCH_NATIVE_SETTINGS; native.c is the TU carrying the implementation. */
#include "pg-clickhouse.h"

#include "../helper.h"
#include "../native.h"
#include "copy.h"

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
 * Decomposition of an Azure URL into the arguments that `azureBlobStorage()`
 * expects.
 */
typedef struct azureURLParts {
    char* account_url;
    char* container;
    char* path;
} azureURLParts;

/* Creates the chDB query for a COPY. */
static size_t
make_ch_query(chdbCopyContext* ctx, StringInfo query, char** names, char** values);

/* Parses `url` into `parts`. */
static void
parse_azure_url(chdbCopyContext*, azureURLParts* parts);

/* Extracts and returns the local file path from `url`. */
static char*
get_local_path_from_file_url(const char* url);

/*
 * Structure clause for the columns `attnums` names, similar to how
 * pgch_structure_from_tupdesc builds for a whole relation. A COPY column list
 * decides which columns cross, so the clause has to follow it.
 */
static char*
structure_for_attnums(TupleDesc desc, List* attnums) {
    StringInfoData buf;

    initStringInfo(&buf);
    ListCell* lc;
    foreach (lc, attnums) {
        Form_pg_attribute attr = TupleDescAttr(desc, lfirst_int(lc) - 1);

        if (buf.len) {
            appendStringInfoString(&buf, ", ");
        }
        appendStringInfo(
            &buf,
            "%s %s",
            pgch_quote_ch_ident(NameStr(attr->attname)),
            pgch_ch_type_for(attr->atttypid, attr->atttypmod, attr->attnotnull, NULL)
        );
    }

    return buf.data;
}

/*
 * Return a copy of `structure` with every bare `type` clause replaced with
 * `String`.
 */
static char*
structure_as_string(const char* structure, const char* type) {
    StringInfoData buf;
    size_t len  = strlen(type);
    bool quoted = false;

    initStringInfo(&buf);
    for (const char* pos = structure; *pos;) {
        if (*pos == '"') {
            quoted = !quoted;
        }
        if (!quoted && strncmp(pos, type, len) == 0 && pos > structure &&
            (pos[-1] == ' ' || pos[-1] == '(') &&
            (pos[len] == '\0' || pos[len] == ',' || pos[len] == ')')) {
            appendStringInfoString(&buf, "String");
            pos += len;
        } else {
            appendStringInfoChar(&buf, *pos++);
        }
    }
    return buf.data;
}

/*
 * Returns true if `format` is one of the formats lacking Time64 support.
 * In such cases, `Time64(6)` should be replaced with `String`.
 */
static bool
format_lacks_time64(const char* format) {
    static const char* const formats[] = {
        "Parquet",  "Arrow",        "ArrowStream", "ORC",         "Avro",
        "Protobuf", "ProtobufList", "MsgPack",     "BSONEachRow",
    };

    for (size_t i = 0; i < lengthof(formats); i++) {
        if (pg_strcasecmp(format, formats[i]) == 0) {
            return true;
        }
    }
    return false;
}

uint64_t
chdb_copy(chdbCopyContext* ctx) {
    /*
     * A value with no ClickHouse representation falls back to its Postgres
     * output function, which reads both of these GUCs. Take the settings for the
     * copy alone: transaction end restores what the session had.
     */
    int nestlevel = NewGUCNestLevel();

    set_config_option(
        "datestyle", "ISO", PGC_USERSET, PGC_S_SESSION, GUC_ACTION_SAVE, true, 0, false
    );
    set_config_option(
        "timezone", "UTC", PGC_USERSET, PGC_S_SESSION, GUC_ACTION_SAVE, true, 0, false
    );

    /* We always need a structure. */
    if (ctx->structure[0] == '\0') {
        TupleDesc desc = RelationGetDescr(ctx->rel);

        ctx->structure = structure_for_attnums(desc, ctx->attnums);
        if (pg_strcasecmp(ctx->format, "ORC") == 0) {
            ctx->structure = structure_as_string(ctx->structure, "UUID");
        }
        if (format_lacks_time64(ctx->format)) {
            ctx->structure = structure_as_string(ctx->structure, "Time64(6)");
        }
    } else {
        /* Workaround for https://github.com/chdb-io/chdb-core/issues/158. */
        for (char* cursor = ctx->structure; *cursor != '\0'; cursor++) {
            if (*cursor == '\n' || *cursor == '\r') {
                *cursor = ' ';
            }
        }
    }

    /* Assemble the chDB query. */
    StringInfoData ch_query;
    initStringInfo(&ch_query);

    char* names[CHDB_MAX_TABLEFUNC_ARGS];
    char* values[CHDB_MAX_TABLEFUNC_ARGS];
    size_t param_count = make_ch_query(ctx, &ch_query, names, values);

    /* Hand off to the helper. */
    chdbHelper* helper =
        chdb_helper_start(ctx->cmd_type, ch_query.data, names, values, param_count);
    uint64_t num_rows =
        ctx->cmd_type == CHDB_CMD_SELECT
            ? chdb_native_receive(
                  ctx->rel, ctx->attnums, ctx->rtable, ctx->rteperminfos, helper
              )
            : chdb_native_send(ctx->rel, ctx->structure, ctx->attnums, helper);
    chdb_helper_finish(helper);

    AtEOXact_GUC(true, nestlevel);

    return num_rows;
}

/* Convenience constant function to append a parameter to a query. */
#define PARAM(format, name, val)                                                       \
    Assert(i + 1 <= CHDB_MAX_TABLEFUNC_ARGS);                                          \
    appendStringInfoString(query, format);                                             \
    names[i]  = name;                                                                  \
    values[i] = val;                                                                   \
    i++;

static const char settings[] =
    "allow_experimental_nullable_tuple_type=1, "
    "output_format_json_quote_denormals=1, " PGCH_NATIVE_SETTINGS;

#define GCS_HOST "storage.googleapis.com"
#define AWS_HOST ".amazonaws.com"

static size_t
make_ch_query(chdbCopyContext* ctx, StringInfo query, char** names, char** values) {
    /* Start the query. */
    appendStringInfo(
        query,
        "%s %s(",
        ctx->cmd_type == CHDB_CMD_SELECT ? "SELECT * FROM" : "INSERT INTO FUNCTION",
        table_function[ctx->scheme]
    );

    /*
     * TODO: For streaming queries, the buffer is sized to fit one block of
     * output: each fetch returns up to max_block_size rows (default 65409).
     * Consider estimating row size and adjusting the batch size accordingly.
     * Use `SETTINGS max_block_size = N` to set it per-query.
     */

    size_t i = 0;
    /* chDB infers a format the copy did not name from the file extension. */
    char* format = ctx->format[0] ? ctx->format : "auto";

    switch (ctx->scheme) {
    case s3_scheme:
    case gcs_scheme: {
        /*
         * https://clickhouse.com/docs/sql-reference/table-functions/s3#syntax
         * https://clickhouse.com/docs/sql-reference/table-functions/gcs#syntax
         */

        /* First parameter: the base URL. */
        char* uri = strstr(ctx->url, "://");
        if (!uri) {
            /* Should not happen, validated by the hook. */
            elog(
                ERROR,
                "chdb: malformed %s URL %s",
                table_function[ctx->scheme],
                ctx->url
            );
        }
        uri += strlen("://");
        char* slash = strchr(uri, '/');

        if (ctx->scheme == s3_scheme) {
            if (slash && slash - uri >= strlen(AWS_HOST) &&
                !pg_strncasecmp(slash - strlen(AWS_HOST), AWS_HOST, strlen(AWS_HOST))) {
                /* s3://{bucket}.{region}.amazonaws.com/{path} */
                PARAM("{url:String}", "url", psprintf("https://%s", uri));
            } else {
                /* s3://{bucket}/{path} */
                PARAM("{url:String}", "url", ctx->url);
            }
        } else {
            /* If it contains the host name, just emit. */
            if (slash && (slash - uri) >= strlen(GCS_HOST) &&
                !pg_strncasecmp(uri, GCS_HOST, strlen(GCS_HOST))) {
                /* gs://storage.googleapis.com/{bucket}/{path} */
                PARAM("{url:String}", "url", psprintf("https://%s", uri));
            } else {
                /* gs://{bucket}/{path} */
                PARAM("{url:String}", "url", psprintf("https://%s/%s", GCS_HOST, uri));
            }
        }

        if (ctx->access_key[0] != '\0') {
            /* access_key implies access secret and maybe s3 session_token. */
            PARAM(", {access_key:String}", "access_key", ctx->access_key);
            PARAM(", {access_secret:String}", "access_secret", ctx->access_secret);
            if (ctx->session_token[0] != '\0' && ctx->scheme == s3_scheme) {
                PARAM(", {session_token:String}", "session_token", ctx->session_token);
            }
        } else {
            /*
             * Consider adding a superuser-only GUC to allow using environment
             * or file credentials. If enabled we'd simply omit this parameter
             * and append the `s3_allow_server_credentials_in_user_queries=1`
             * setting.
             */
            appendStringInfoString(query, ", NOSIGN");
        }

        /* Append remaining arguments and settings. */
        PARAM(", {format:String}", "format", format);
        PARAM(", {structure:String}", "structure", ctx->structure);
        if (ctx->compression[0] != '\0') {
            PARAM(", {compression:String}", "compression", ctx->compression);
        }
        appendStringInfo(
            query,
            ") SETTINGS %s, s3_truncate_on_insert = 1, s3_request_timeout_ms = %u",
            settings,
            ctx->timeout
        );
        break;
    }
    case http_scheme:
        /* https://clickhouse.com/docs/sql-reference/table-functions/url#syntax */

        /* First parameter: the base URL. */
        PARAM("{url:String}", "url", ctx->url);
        PARAM(", {format:String}", "format", format);
        PARAM(", {structure:String}", "structure", ctx->structure);
        appendStringInfo(
            query,
            ") SETTINGS %s, http_connection_timeout=%u, http_max_tries=1",
            settings,
            (uint32_t)ceil(ctx->timeout / (double)1000)
        );
        break;
    case az_scheme:
    case abfs_scheme: {
        /*
         * https://clickhouse.com/docs/sql-reference/table-functions/azureBlobStorage#syntax
         */

        /* Parse the Azure URL to get the account URL, container, and path. */
        azureURLParts parts;
        parse_azure_url(ctx, &parts);

        /* Append required args. */
        PARAM("{url:String}", "url", parts.account_url);
        PARAM(", {container:String}", "container", parts.container);
        PARAM(", {path:String}", "path", parts.path);
        PARAM(", {account_name:String}", "account_name", ctx->access_key);
        PARAM(", {account_key:String}", "account_key", ctx->access_secret);

        /* Append remaining arguments (different order from the others) and
         * settings. */
        PARAM(", {format:String}", "format", format);
        PARAM(
            ", {compression:String}",
            "compression",
            ctx->compression[0] ? ctx->compression : "auto"
        );
        PARAM(", {structure:String}", "structure", ctx->structure);
        appendStringInfo(
            query,
            ") SETTINGS %s, azure_truncate_on_insert = 1, azure_request_timeout_ms=%u",
            settings,
            ctx->timeout
        );
        break;
    }
    case file_scheme:
        /* https://clickhouse.com/docs/sql-reference/table-functions/file#syntax */

        /* First parameter: the path to the file. */
        PARAM("{path:String}", "path", get_local_path_from_file_url(ctx->url));

        /* Append remaining arguments and settings. */
        PARAM(", {format:String}", "format", format);
        PARAM(", {structure:String}", "structure", ctx->structure);
        if (ctx->compression[0] != '\0') {
            PARAM(", {compression:String}", "compression", ctx->compression);
        }
        appendStringInfo(
            query, ") SETTINGS %s, engine_file_truncate_on_insert=1", settings
        );
        break;
    case hdfs_scheme:
        /* https://clickhouse.com/docs/sql-reference/table-functions/hdfs#syntax */

        /* First parameter: the base URL. */
        PARAM("{url:String}", "url", ctx->url);

        /* Append remaining arguments and settings. */
        PARAM(", {format:String}", "format", format);
        PARAM(", {structure:String}", "structure", ctx->structure);
        appendStringInfo(query, ") SETTINGS %s, hdfs_truncate_on_insert = 1", settings);
        break;
    default:
        elog(ERROR, "unsupported URL scheme %d", ctx->scheme);
        break;
    }

    /* Every branch above ends in a SETTINGS clause, so this joins it. */
    if (ctx->max_memory > 0) {
        appendStringInfo(query, ", max_memory_usage=" INT64_FORMAT, ctx->max_memory);
    }

    if (
#if PG_VERSION_NUM >= 190000
        log_min_messages[MyBackendType] <= DEBUG1
#else
        log_min_messages <= DEBUG1
#endif
    ) {
        /* Reassemble params for logging. */
        StringInfoData params;
        initStringInfo(&params);
        bool first = true;
        for (size_t j = 0; j < i; j++) {
            if (!first) {
                appendStringInfoString(&params, ", ");
            }
            appendStringInfo(&params, "%s: \"%s\"", names[j], values[j]);
            first = false;
        }

        /* Log the query and params for the TAP tests to examine. */
        ereport(
            LOG_SERVER_ONLY,
            errmsg("executing chDB query"),
            errdetail("query: %s", query->data),
            errcontext("params: { %s }", params.data)
        );
    }

    return i;
}

/*
* Decomposition of an Azure URL into the arguments the `azureBlobStorage`
  engine expects.
*/
static void
parse_azure_url(chdbCopyContext* ctx, azureURLParts* parts) {
    /*
     * Based on Azure URL parsing for the url() function in ClickHouse 26.7:
     * https://github.com/ClickHouse/ClickHouse/blob/0b235b0/src/Storages/StorageURL.cpp#L2016-L2087
     */
    char* uri = strstr(ctx->url, "://");
    if (!uri) {
        /* Should not happen, validated by the hook. */
        elog(ERROR, "chdb: malformed Azure URL %s", ctx->url);
    }

    uri += 3;

    /*
     * Split off the query string (a SAS token such as `?sp=...&sig=...`)
     * before parsing the host and path.
     */
    char* query = strchr(uri, '?');
    if (query) {
        /* NUL terminate the URL and split off the query. */
        *query = '\0';
        query++;
    }

    /*
     * Hadoop-style
     * `abfss://<container>@<account>.dfs.core.windows.net/<blob path>`.
     */
    if (ctx->scheme == abfs_scheme) {
        char* at = strchr(uri, '@');
        if (!at) {
            ereport(
                ERROR,
                errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                errmsg("chdb: Azure ABFS URL missing the container part"),
                errhint("abfs://<container>@<account>.dfs.core.windows.net/<path>")
            );
        }

        parts->container    = pnstrdup(uri, at - uri);
        char* host_and_path = at + 1;
        char* slash         = strchr(host_and_path, '/');
        char* host =
            slash ? pnstrdup(host_and_path, slash - host_and_path) : host_and_path;
        parts->path        = slash ? slash + 1 : "";
        char* dot          = strchr(host, '.');
        char* account      = dot ? host : psprintf("%s.blob.core.windows.net", host);
        parts->account_url = query ? psprintf("https://%s?%s", account, query)
                                   : psprintf("https://%s", account);
        return;
    }

    /*
     * `<account>.blob.core.windows.net/<container>/<blob>` or
     * `<host>/<container>/<blob>`.
     */
    char* path = strstr(uri, "/");

    /*
     * `az://<account>.blob.core.windows.net/<container>/<blob>` or
     * `azure://<host>/<container>/<blob>`
     */
    const char* host = path ? pnstrdup(uri, path - uri) : uri;
    path             = path ? path + 1 : "";

    char* dot = strchr(host, '.');
    if (!dot) {
        ereport(
            ERROR,
            errcode(ERRCODE_INVALID_PARAMETER_VALUE),
            errmsg("chdb: Azure URL missing the storage account host"),
            errhint("az://<account>.blob.core.windows.net/<container>/<path>")
        );
    }

    parts->account_url =
        query ? psprintf("https://%s?%s", host, query) : psprintf("https://%s", host);
    char* slash = strchr(path, '/');
    parts->container =
        slash ? pnstrdup(path, slash - path) : pnstrdup(path, strlen(path));
    parts->path = slash ? slash + 1 : "";

    if (strlen(parts->container) == 0) {
        ereport(
            ERROR,
            errcode(ERRCODE_INVALID_PARAMETER_VALUE),
            errmsg("chdb: Azure URL missing the container name"),
            errhint("az://<account>.blob.core.windows.net/<container>/<path>")
        );
    }
}

/*
 * Get the local path from a file:// URL. Must be an absolute path or else it
 * raises an error.
 */
static char*
get_local_path_from_file_url(const char* url) {
    /* https://github.com/ClickHouse/ClickHouse/blob/0b235b0/src/Storages/StorageURL.cpp#L2000-L2014*/
    char* path = strstr(url, "://");
    if (!path) {
        /* Should not happen, validated by the hook. */
        elog(ERROR, "chdb: malformed file URL %s", url);
    }

    path += 3;
    if (!is_absolute_path(path)) {
        ereport(
            ERROR,
            errcode(ERRCODE_INVALID_NAME),
            errmsg("chdb: relative path not allowed for COPY to file URL")
        );
    }

    return path;
}


#include "postgres.h"

#include "catalog/namespace.h"
#include "libpq/pqformat.h"
#include "libpq/pqmq.h"
#include "miscadmin.h"
#include "nodes/pg_list.h"
#include "postmaster/bgworker.h"
#include "storage/dsm.h"
#include "storage/proc.h"
#include "storage/shm_toc.h"
#include "tcop/cmdtag.h"
#include "tcop/utility.h"
#include "utils/lsyscache.h"
#include "utils/rel.h"

#include "bgw/worker.h"

/* previous hook */
static ProcessUtility_hook_type PrevProcessUtility = NULL;

/* The chDB process utility hook. */
static void
chDBProcessUtilityHook(
    PlannedStmt* plannedStmt,
    const char* queryString,
    bool readOnlyTree,
    ProcessUtilityContext context,
    ParamListInfo params,
    struct QueryEnvironment* queryEnv,
    DestReceiver* dest,
    QueryCompletion* completionTag
);

/* Initializes the chDB process utility hook. */
void
InitializeUtilityHook(void);
void
LaunchWorker(chdbCopyContext* ctx);
scheme
scheme_for(const char* str);
static void
contextualize_options(chdbCopyContext* ctx, List* options);
void
ProcessMessages(shm_mq_handle* queue);

/*
 * InitializeUtilityHook hooks chDBProcessUtilityHook into the process utility
 * hook to in order to intercept DDL commands.
 */
void
InitializeUtilityHook(void) {
    PrevProcessUtility =
        ProcessUtility_hook ? ProcessUtility_hook : standard_ProcessUtility;
    ProcessUtility_hook = chDBProcessUtilityHook;
}

scheme
scheme_for(const char* str) {
    if (str) {
        char* ptr = strstr(str, "://");
        if (ptr) {
            size_t len = ptr - str;

            for (size_t sch = http_scheme; sch < no_scheme; sch++) {
                if (strlen(scheme_name[sch]) == len &&
                    memcmp(str, scheme_name[sch], len) == 0) {
                    return sch;
                }
            }
        }
    }

    return no_scheme;
}

static void
contextualize_options(chdbCopyContext* ctx, List* options) {
    ListCell* lc;
    ctx->access_key    = "";
    ctx->access_secret = "";
    ctx->session_token = "";
    ctx->format        = "";
    ctx->structure     = "";
    ctx->compression   = "";

    foreach (lc, options) {
        DefElem* elem = (DefElem*)lfirst(lc);
        char* pname   = elem->defname;
        char* pval    = strVal(elem->arg);
        if (strcmp(pname, "access_key") == 0) {
            ctx->access_key = pval;
        } else if (strcmp(pname, "access_secret") == 0) {
            ctx->access_secret = pval;
        } else if (strcmp(pname, "session_token") == 0) {
            ctx->session_token = pval;
        } else if (strcmp(pname, "format") == 0) {
            ctx->format = pval;
        } else if (strcmp(pname, "structure") == 0) {
            ctx->structure = pval;
        } else if (strcmp(pname, "compression") == 0) {
            ctx->compression = pval;
        } else {
            ereport(
                WARNING,
                errcode(ERRCODE_WARNING),
                errmsg("chdb does not support COPY option %s", pname)
            );
        }
    }
}

/*
 * PgLakeCommonProcessUtility modifies the behaviour of DDL commands.
 */
static void
chDBProcessUtilityHook(
    PlannedStmt* plannedStmt,
    const char* queryString,
    bool readOnlyTree,
    ProcessUtilityContext context,
    ParamListInfo params,
    struct QueryEnvironment* queryEnv,
    DestReceiver* dest,
    QueryCompletion* completionTag
) {
    Node* parsetree = plannedStmt->utilityStmt;

    /* Is this a COPY statement? */
    if (IsA(parsetree, CopyStmt)) {
        /* Look for a URL filename. */
        CopyStmt* copy = (CopyStmt*)parsetree;
        scheme scheme  = scheme_for(copy->filename);
        if (scheme != no_scheme) {
            /* We own this copy. Fire up a worker to execute it. */
            char* schema = copy->relation->schemaname
                               ? copy->relation->schemaname
                               : get_namespace_name(get_rel_namespace(
                                     RangeVarGetRelid(copy->relation, NoLock, true)
                                 ));
            chdbCopyContext ctx = {
                .extra = {
                    .scheme  = scheme,
                    .db_id   = MyDatabaseId,
                    .role_id = GetAuthenticatedUserId(),
                    .is_from = copy->is_from
                    // .session_user_id = GetSessionUserId(),
                    // .outer_user_id = GetCurrentRoleId(),
                 },
                .table   = copy->relation->relname,
                .schema  = schema,
                .url     = copy->filename,
            };
            contextualize_options(&ctx, copy->options);
            LaunchWorker(&ctx);

            return;
        }
    }

    /* Continue with the internal execution. */
    PrevProcessUtility(
        plannedStmt,
        queryString,
        readOnlyTree,
        context,
        params,
        queryEnv,
        dest,
        completionTag
    );
}

/*
 * Dynamically launch a chDB worker.
 */
void
LaunchWorker(chdbCopyContext* ctx) {
    /* Size the shared memory for the chdbCopyContext. */
    shm_toc_estimator estimator;

    shm_toc_initialize_estimator(&estimator);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->schema) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->table) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->url) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->access_key) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->access_secret) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->session_token) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->format) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->structure) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->compression) + 1);
    shm_toc_estimate_chunk(&estimator, CHDB_ERROR_QUEUE_SIZE);
    shm_toc_estimate_keys(&estimator, CHDB_NUM_SHM_KEYS);

    /* Create the shared memory segment. */
    Size seg_size    = shm_toc_estimate(&estimator);
    dsm_segment* seg = dsm_create(seg_size, 0);

    /* Copy the context strings into the shared memory segment. */
    shm_toc* toc = shm_toc_create(CHDB_SHM_MAGIC, dsm_segment_address(seg), seg_size);

    char* string_shm = shm_toc_allocate(toc, strlen(ctx->schema) + 1);
    strcpy(string_shm, ctx->schema);
    shm_toc_insert(toc, CHDB_KEY_SCHEMA, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->table) + 1);
    strcpy(string_shm, ctx->table);
    shm_toc_insert(toc, CHDB_KEY_TABLE, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->url) + 1);
    strcpy(string_shm, ctx->url);
    shm_toc_insert(toc, CHDB_KEY_URL, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->access_key) + 1);
    strcpy(string_shm, ctx->access_key);
    shm_toc_insert(toc, CHDB_KEY_ACCESS_KEY, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->access_secret) + 1);
    strcpy(string_shm, ctx->access_secret);
    shm_toc_insert(toc, CHDB_KEY_ACCESS_SECRET, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->session_token) + 1);
    strcpy(string_shm, ctx->session_token);
    shm_toc_insert(toc, CHDB_KEY_SESSION_TOKEN, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->format) + 1);
    strcpy(string_shm, ctx->format);
    shm_toc_insert(toc, CHDB_KEY_FORMAT, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->structure) + 1);
    strcpy(string_shm, ctx->structure);
    shm_toc_insert(toc, CHDB_KEY_STRUCTURE, string_shm);

    string_shm = shm_toc_allocate(toc, strlen(ctx->compression) + 1);
    strcpy(string_shm, ctx->compression);
    shm_toc_insert(toc, CHDB_KEY_COMPRESSION, string_shm);

    /* Set up the error queue. */
    shm_mq* err_queue = shm_mq_create(
        shm_toc_allocate(toc, CHDB_ERROR_QUEUE_SIZE), CHDB_ERROR_QUEUE_SIZE
    );
    shm_toc_insert(toc, CHDB_KEY_ERROR_QUEUE, err_queue);
    shm_mq_set_receiver(err_queue, MyProc);
    shm_mq_handle* mqh = shm_mq_attach(err_queue, seg, NULL);

    /* Create the worker. */
    BackgroundWorker worker;
    memset(&worker, 0, sizeof(worker));
    worker.bgw_flags = BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;
    worker.bgw_start_time   = BgWorkerStart_RecoveryFinished;
    worker.bgw_restart_time = BGW_NEVER_RESTART;
    sprintf(worker.bgw_library_name, "chdb_bgw");
    sprintf(worker.bgw_function_name, "chdb_bgw_main");
    snprintf(worker.bgw_name, BGW_MAXLEN, "chdb %s.%s worker", ctx->schema, ctx->table);
    snprintf(worker.bgw_type, BGW_MAXLEN, "chdb_bgw dynamic");
    worker.bgw_main_arg   = UInt32GetDatum(dsm_segment_handle(seg));
    worker.bgw_notify_pid = MyProcPid;

    /* Send the fixed size values via bgw_extra. */
    StaticAssertDecl(
        sizeof(struct chdbCopyExtra) <= BGW_EXTRALEN,
        "chdbCopyExtra is to large to fix into BackgroundWorker.bgw_extra"
    );
    memcpy(worker.bgw_extra, &ctx->extra, sizeof(chdbCopyExtra));

    /* Register the worker. */
    BackgroundWorkerHandle* handle;
    if (!RegisterDynamicBackgroundWorker(&worker, &handle)) {
        dsm_detach(seg);
        /* Wording copied from Postgres source, will be localized. */
        ereport(
            ERROR,
            errcode(ERRCODE_CONFIGURATION_LIMIT_EXCEEDED),
            errmsg("out of background worker slots"),
            errhint("You might need to increase max_worker_processes.")
        );
    }

    /* Associate this worker with the message queue. */
    shm_mq_set_handle(mqh, handle);

    /* Wait for the background worker to start */
    pid_t pid;
    BgwHandleStatus status = WaitForBackgroundWorkerStartup(handle, &pid);

    if (status == BGWH_STOPPED) {
        dsm_detach(seg);
        ereport(
            ERROR,
            (errcode(ERRCODE_INSUFFICIENT_RESOURCES),
             errmsg("could not start background process"),
             errhint("More details may be available in the server log."))
        );
    }
    if (status == BGWH_POSTMASTER_DIED) {
        ereport(
            ERROR,
            (errcode(ERRCODE_INSUFFICIENT_RESOURCES),
             errmsg("cannot start background processes without postmaster"),
             errhint("Kill all remaining database processes and restart the database."))
        );
    }
    Assert(status == BGWH_STARTED);

    /* Wait for it to finish. */
    PG_TRY();
    { ProcessMessages(mqh); }
    PG_FINALLY();
    { dsm_detach(seg); }
    PG_END_TRY();

    WaitForBackgroundWorkerShutdown(handle);
}

/*
 * ProcessMessages consumes all messages from queue until it finishes. If it
 * reads an error message it throws the error. Otherwise it returns once the
 * queue has been drained.
 */
void
ProcessMessages(shm_mq_handle* queue) {
    Size msg_len;
    void* data;
    StringInfoData msg;

    for (;;) {
        CHECK_FOR_INTERRUPTS();

        shm_mq_result res = shm_mq_receive(queue, &msg_len, &data, false);
        if (res != SHM_MQ_SUCCESS) {
            ereport(
                ERROR,
                errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                errmsg("lost connection to chdb worker")
            );
        }

        initStringInfo(&msg);
        appendBinaryStringInfo(&msg, data, msg_len);
        int msg_type = pq_getmsgbyte(&msg);

        switch (msg_type) {
        case PqMsg_ErrorResponse:
        case PqMsg_NoticeResponse: {
            /* Read in the error and throw it. */
            ErrorData err;
            pq_parse_errornotice(&msg, &err);

            /* Death of a worker isn't enough justification for suicide. */
            err.elevel = Min(err.elevel, ERROR);

            /* Clean up and rethrow error or print notice. */
            pfree(msg.data);
            ThrowErrorData(&err);
            break;
        }
        case PqMsg_Terminate:
            /* Successful termination. */
            pfree(msg.data);
            return;

        default:
            pfree(msg.data);
            elog(
                WARNING, "unexpected message type: %c (%zu bytes)", msg.data[0], msg_len
            );
            break;
        }
    }
}

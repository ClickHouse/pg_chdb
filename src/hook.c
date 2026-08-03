

#include "postgres.h"

#include "access/sysattr.h"
#include "access/table.h"
#include "catalog/namespace.h"
#include "catalog/pg_authid.h"
#include "commands/copy.h"
#include "commands/defrem.h"
#include "executor/executor.h"
#include "libpq/pqformat.h"
#include "libpq/pqmq.h"
#include "miscadmin.h"
#include "nodes/nodes.h"
#include "parser/parse_node.h"
#include "parser/parse_relation.h"
#include "storage/shm_toc.h"
#include "tcop/utility.h"
#include "utils/acl.h"
#include "utils/builtins.h"
#include "utils/rel.h"
#include "utils/rls.h"
#if PG_VERSION_NUM >= 190000
#include "storage/proc.h"
#endif

#ifndef SCNu32
#include <inttypes.h>
#endif

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
LaunchWorker(chdbCopyContext* ctx, QueryCompletion* qc);
scheme
scheme_for(const char* str);
static void
check_server_file_privileges(bool is_from);
static Relation
open_copy_relation(CopyStmt* copy);
static void
contextualize_options(chdbCopyContext* ctx, List* options);
void
ProcessMessages(shm_mq_handle* queue, QueryCompletion* qc);

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
                for (size_t i = 0; scheme_name[sch][i]; i++) {
                    if (strlen(scheme_name[sch][i]) == len &&
                        memcmp(str, scheme_name[sch][i], len) == 0) {
                        return sch;
                    }
                }
            }
        }
    }

    return no_scheme;
}

/*
 * A file:// URL reads and writes files on the server, which Postgres gates on
 * membership in a role. Apply the same gate as DoCopy() does.
 */
static void
check_server_file_privileges(bool is_from) {
    if (is_from) {
        if (!has_privs_of_role(GetUserId(), ROLE_PG_READ_SERVER_FILES)) {
            ereport(
                ERROR,
                errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
                errmsg("chdb: permission denied to COPY from a file"),
                errdetail(
                    "Only roles with privileges of the \"pg_read_server_files\" role "
                    "may COPY from a file."
                )
            );
        }
    } else if (!has_privs_of_role(GetUserId(), ROLE_PG_WRITE_SERVER_FILES)) {
        ereport(
            ERROR,
            errcode(ERRCODE_INSUFFICIENT_PRIVILEGE),
            errmsg("chdb: permission denied to COPY to a file"),
            errdetail(
                "Only roles with privileges of the \"pg_write_server_files\" role may "
                "COPY to a file."
            )
        );
    }
}

/*
 * Opens and locks relation named by COPY statement, with privilege checks that
 * DoCopy() applies to a normal COPY: INSERT or SELECT on relation or on each
 * copied column, then row-level security. Errors out unless the current user
 * may copy the relation. Returns the locked relation; the caller must close it.
 */
static Relation
open_copy_relation(CopyStmt* copy) {
    LOCKMODE lockmode = copy->is_from ? RowExclusiveLock : AccessShareLock;
    Relation rel      = table_openrv(copy->relation, lockmode);

    ParseState* pstate = make_parsestate(NULL);
    ParseNamespaceItem* nsitem =
        addRangeTableEntryForRelation(pstate, rel, lockmode, NULL, false, false);
    RTEPermissionInfo* perminfo = nsitem->p_perminfo;
    perminfo->requiredPerms     = copy->is_from ? ACL_INSERT : ACL_SELECT;

    /* Only the copied columns require privileges. */
    Bitmapset** cols =
        copy->is_from ? &perminfo->insertedCols : &perminfo->selectedCols;
    ListCell* lc;
    foreach (lc, CopyGetAttnums(RelationGetDescr(rel), rel, copy->attlist)) {
        *cols =
            bms_add_member(*cols, lfirst_int(lc) - FirstLowInvalidHeapAttributeNumber);
    }
    ExecCheckPermissions(pstate->p_rtable, list_make1(perminfo), true);

    /*
     * chDB copies the whole relation, so policies cannot be applied to the
     * rows. Postgres runs a query-based COPY TO, which we don't yet support.
     */
    if (check_enable_rls(RelationGetRelid(rel), InvalidOid, false) == RLS_ENABLED) {
        ereport(
            ERROR,
            errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
            errmsg(
                "chdb: COPY %s not supported with row-level security",
                copy->is_from ? "FROM" : "TO"
            ),
            errdetail(
                "Row-level security policies apply to relation \"%s\" for this role.",
                RelationGetRelationName(rel)
            )
        );
    }

    if (RelationUsesLocalBuffers(rel)) {
        ereport(
            ERROR,
            errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
            errmsg(
                "chdb: cannot COPY temporary relation \"%s\"",
                RelationGetRelationName(rel)
            ),
            errdetail(
                "Temporary relations are visible only to the session that "
                "created them, not to the chdb worker."
            )
        );
    }

    return rel;
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
    ctx->extra.timeout = 30000; /* Same as ClickHouse. */

    foreach (lc, options) {
        DefElem* elem = (DefElem*)lfirst(lc);
        if (strcmp(elem->defname, "access_key") == 0) {
            ctx->access_key = defGetString(elem);
        } else if (strcmp(elem->defname, "access_secret") == 0) {
            ctx->access_secret = defGetString(elem);
        } else if (strcmp(elem->defname, "session_token") == 0) {
            ctx->session_token = defGetString(elem);
        } else if (strcmp(elem->defname, "format") == 0) {
            ctx->format = defGetString(elem);
        } else if (strcmp(elem->defname, "structure") == 0) {
            ctx->structure = defGetString(elem);
        } else if (strcmp(elem->defname, "compression") == 0) {
            ctx->compression = defGetString(elem);
        } else if (strcmp(elem->defname, "timeout") == 0) {
            int64 timeout = defGetInt64(elem);
            if (timeout < 0 || timeout > UINT32_MAX) {
                ereport(
                    ERROR,
                    errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                    errmsg("chdb: argument to COPY option \"timeout\" must be a uint32")
                );
            }
            ctx->extra.timeout = (uint32_t)timeout;
        } else {
            ereport(
                ERROR,
                errcode(ERRCODE_SYNTAX_ERROR),
                errmsg("chdb: option \"%s\" not supported", elem->defname)
            );
        }
    }
}

/*
 * chDBProcessUtilityHook modifies the behaviour of DDL commands.
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
    QueryCompletion* qc
) {
    Node* parsetree = plannedStmt->utilityStmt;

    /* Is this a COPY statement? */
    if (IsA(parsetree, CopyStmt)) {
        /* Look for a URL filename. */
        CopyStmt* copy = (CopyStmt*)parsetree;
        scheme scheme  = scheme_for(copy->filename);

        /* Leave COPY TO/FROM PROGRAM to Postgres, which gates it on a role. */
        if (copy->relation && !copy->is_program && scheme != no_scheme) {
            /* We own this copy, but only if the user may copy the relation. */
            if (copy->is_from) {
                PreventCommandIfReadOnly("COPY FROM");
            }
            if (scheme == file_scheme) {
                check_server_file_privileges(copy->is_from);
            }
            Relation rel = open_copy_relation(copy);
            chdbCopyContext ctx = {
                .extra = {
                    .scheme  = scheme,
                    .rel_id = RelationGetRelid(rel),
                    .db_id   = MyDatabaseId,
                    .role_id = GetAuthenticatedUserId(),
                    .is_from = copy->is_from
                    // .session_user_id = GetSessionUserId(),
                    // .outer_user_id = GetCurrentRoleId(),
                 },
                .url     = copy->filename,
                .attlist = copy->attlist ? nodeToString(copy->attlist) : "",
            };

            /* The worker copies as the role whose privileges we just checked. */
            GetUserIdAndSecContext(&ctx.extra.user_id, &ctx.extra.sec_context);
            contextualize_options(&ctx, copy->options);

            /* Retain the lock until commit so the worker copies what we checked. */
            table_close(rel, NoLock);
            LaunchWorker(&ctx, qc);

            return;
        }
    }

    /* Continue with the internal execution. */
    PrevProcessUtility(
        plannedStmt, queryString, readOnlyTree, context, params, queryEnv, dest, qc
    );
}

/*
 * Dynamically launch a chDB worker.
 */
void
LaunchWorker(chdbCopyContext* ctx, QueryCompletion* qc) {
    /* Size the shared memory for the chdbCopyContext. */
    shm_toc_estimator estimator;

    /* Estimate the share memory sizing for query parameters. */
    shm_toc_initialize_estimator(&estimator);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->url) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->access_key) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->access_secret) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->session_token) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->format) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->structure) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->compression) + 1);
    shm_toc_estimate_chunk(&estimator, strlen(ctx->attlist) + 1);
    shm_toc_estimate_chunk(&estimator, CHDB_ERROR_QUEUE_SIZE);
    shm_toc_estimate_keys(&estimator, CHDB_NUM_SHM_KEYS);

    /* Create the shared memory segment. */
    Size seg_size    = shm_toc_estimate(&estimator);
    dsm_segment* seg = dsm_create(seg_size, 0);

    /* Copy the context strings into the shared memory segment. */
    shm_toc* toc = shm_toc_create(CHDB_SHM_MAGIC, dsm_segment_address(seg), seg_size);

    char* string_shm = shm_toc_allocate(toc, strlen(ctx->url) + 1);
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

    string_shm = shm_toc_allocate(toc, strlen(ctx->attlist) + 1);
    strcpy(string_shm, ctx->attlist);
    shm_toc_insert(toc, CHDB_KEY_ATTLIST, string_shm);

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
    snprintf(
        worker.bgw_name,
        BGW_MAXLEN,
        "chdb %s worker",
        DatumGetCString(
            DirectFunctionCall1(regclassout, ObjectIdGetDatum(ctx->extra.rel_id))
        )
    );
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
            errmsg("chdb: out of background worker slots"),
            errhint("You might need to increase max_worker_processes.")
        );
    }

    /* Associate this worker with the message queue. */
    shm_mq_set_handle(mqh, handle);

    /* Wait for the background worker to start */
    pid_t pid;
    BgwHandleStatus status = WaitForBackgroundWorkerStartup(handle, &pid);

    if (status == BGWH_POSTMASTER_DIED) {
        ereport(
            ERROR,
            (errcode(ERRCODE_INSUFFICIENT_RESOURCES),
             errmsg("chdb: cannot start background processes without postmaster"),
             errhint("Kill all remaining database processes and restart the database."))
        );
    }

    /*
     * BGWH_STOPPED also covers a worker that already ran to completion, with
     * its messages waiting in the queue, so fall through to drain it.
     */
    Assert(status == BGWH_STARTED || status == BGWH_STOPPED);

    /* Wait for it to finish. */
    PG_TRY();
    { ProcessMessages(mqh, qc); }
    PG_CATCH();
    {
        dsm_detach(seg);
        TerminateBackgroundWorker(handle);
        WaitForBackgroundWorkerShutdown(handle);
        PG_RE_THROW();
    }
    PG_END_TRY();

    dsm_detach(seg);
    WaitForBackgroundWorkerShutdown(handle);
}

/*
 * ProcessMessages consumes all messages from queue until it finishes. If it
 * reads an error message it throws the error. Otherwise it returns once the
 * queue has been drained.
 */
void
ProcessMessages(shm_mq_handle* queue, QueryCompletion* qc) {
    Size msg_len;
    void* data;
    StringInfoData msg;
    initStringInfo(&msg);

    for (;;) {
        CHECK_FOR_INTERRUPTS();

        /*
         * shm_mq_receive drains fully written messages before SHM_MQ_DETACHED,
         * and detects a worker that dies before attaching as sender.
         * Detach without PqMsg_Terminate means the worker died.
         */
        shm_mq_result res = shm_mq_receive(queue, &msg_len, &data, false);
        if (res != SHM_MQ_SUCCESS) {
            ereport(
                ERROR,
                errcode(ERRCODE_OBJECT_NOT_IN_PREREQUISITE_STATE),
                errmsg("chdb: the background worker died")
            );
        }

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

            /* Rethrow error or print notice, then reset. */
            ThrowErrorData(&err);
            resetStringInfo(&msg);
            break;
        }
        case PqMsg_Progress: {
            /* Progress report. See pgstat_progress_parallel_incr_param for format. */
            CommandTag cmd = pq_getmsgint(&msg, sizeof(uint32_t));
            SetQueryCompletion(qc, cmd, pq_getmsgint64(&msg));
            resetStringInfo(&msg);
            break;
        }
        case PqMsg_Terminate:
            /* Successful termination. */
            pfree(msg.data);
            return;

        default:
            resetStringInfo(&msg);
            elog(
                WARNING, "unexpected message type: %c (%zu bytes)", msg.data[0], msg_len
            );
            break;
        }
    }
}

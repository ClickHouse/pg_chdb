
#include "postgres.h"

#include "bgw/worker.h"
#include "miscadmin.h"
#include "nodes/pg_list.h"
#include "postmaster/bgworker.h"
#include "tcop/cmdtag.h"
#include "tcop/utility.h"
#include "utils/builtins.h"

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
        } else if (strcmp(pname, "headers") == 0) {
            ctx->headers = pval;
        } else if (strcmp(pname, "extra_credentials") == 0) {
            ctx->extra_credentials = pval;
        } else {
            ereport(
                NOTICE,
                errcode(ERRCODE_FDW_INVALID_OPTION_NAME),
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
            chdbCopyContext ctx = {
                .scheme  = scheme,
                .dboid   = MyDatabaseId,
                .roleoid = GetAuthenticatedUserId(),
                // .session_user_id = GetSessionUserId(),
                // .outer_user_id = GetCurrentRoleId(),
                .table  = copy->relation->relname,
                .schema = copy->relation->schemaname,
                .url    = copy->filename,
            };
            contextualize_options(&ctx, copy->options);
            LaunchWorker(&ctx);

            elog(
                NOTICE,
                "COPY %s %s %s(%s)",
                quote_identifier(copy->relation->relname),
                copy->is_from ? "FROM" : "TO",
                table_function[scheme],
                quote_literal_cstr(copy->filename)
            );

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
    BackgroundWorker worker;
    BackgroundWorkerHandle* handle;
    BgwHandleStatus status;
    pid_t pid;

    memset(&worker, 0, sizeof(worker));
    worker.bgw_flags = BGWORKER_SHMEM_ACCESS | BGWORKER_BACKEND_DATABASE_CONNECTION;

    worker.bgw_start_time   = BgWorkerStart_RecoveryFinished;
    worker.bgw_restart_time = BGW_NEVER_RESTART;
    sprintf(worker.bgw_library_name, "chdb_bgw");
    sprintf(worker.bgw_function_name, "chdb_bgw_main");
    snprintf(
        worker.bgw_name, BGW_MAXLEN, "chdb_bgw %s.%s worker", ctx->schema, ctx->table
    );
    snprintf(worker.bgw_type, BGW_MAXLEN, "chdb_bgw dynamic");
    /* set bgw_notify_pid so that we can use WaitForBackgroundWorkerStartup */
    worker.bgw_notify_pid = MyProcPid;
    memcpy(worker.bgw_extra, ctx, sizeof(chdbCopyContext));

    if (!RegisterDynamicBackgroundWorker(&worker, &handle)) {
        return;
    }

    status = WaitForBackgroundWorkerStartup(handle, &pid);

    if (status == BGWH_STOPPED) {
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
    WaitForBackgroundWorkerShutdown(handle);
}

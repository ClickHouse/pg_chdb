
#include "postgres.h"

#include "miscadmin.h"
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

/*
 * PgLakeCommonProcessUtility modifies the behaviour of DDL Commands
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

    /* If it's not a COPY statement, just let it do its thing. */
    if (!IsA(parsetree, CopyStmt)) {
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
        return;
    }

    CopyStmt* copy = (CopyStmt*)parsetree;

    elog(
        NOTICE,
        "LOL, I have prevented COPY from executing against table %s",
        quote_identifier(copy->relation->relname)
    );
}

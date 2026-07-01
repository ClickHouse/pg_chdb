
#include "postgres.h"

#include "miscadmin.h"
#include "nodes/pg_list.h"
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

scheme
scheme_for(const char* str);

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

        // ListCell* lc;
        // foreach (lc, copy->options) {
        //     DefElem* elem = (DefElem*)lfirst(lc);
        //     char* pname   = elem->defname;
        //     if (strcmp(pname, "url") == 0) {
        //         /* Intercept it! */
        //     }
        // }
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

/*
 * Support CREATE TABLE using columns and optional rows from URL supported by chDB
 * Get columns from explicit structure or infer them with DESCRIBE
 */

#include "postgres.h"

#include "catalog/namespace.h"
#include "catalog/pg_type.h"
#include "commands/defrem.h"
#include "nodes/makefuncs.h"
#include "utils/lsyscache.h"

#include "pg-clickhouse.h"

#include "../native.h"
#include "create.h"

/* Remove `name` from `create` options and return its value, or NULL if absent */
static char*
take_url_option(CreateStmt* create, const char* name) {
    ListCell* lc;

    foreach (lc, create->options) {
        DefElem* elem = lfirst(lc);

        if (strcmp(elem->defname, name) == 0) {
            create->options = list_delete_cell(create->options, lc);

            return defGetString(elem);
        }
    }

    return NULL;
}

bool
chdb_creates_from_url(CreateStmt* create) {
    ListCell* lc;

    foreach (lc, create->options) {
        DefElem* elem = lfirst(lc);

        if (strcmp(elem->defname, CHDB_STRUCTURE_FROM) == 0 ||
            strcmp(elem->defname, CHDB_COPY_FROM) == 0) {
            return true;
        }
    }

    return false;
}

/*
 * Report existing relation before requesting remote schema
 * Reject IF NOT EXISTS because subsequent copy requires newly created relation
 */
static void
error_if_relation_exists(CreateStmt* create) {
    Oid nspid = RangeVarGetCreationNamespace(create->relation);

    if (!OidIsValid(get_relname_relid(create->relation->relname, nspid))) {
        return;
    }
    if (create->if_not_exists) {
        ereport(
            ERROR,
            errcode(ERRCODE_DUPLICATE_TABLE),
            errmsg("relation \"%s\" already exists", create->relation->relname),
            errdetail(
                "CREATE TABLE IF NOT EXISTS neither derives columns nor copies rows "
                "from a URL."
            ),
            errhint("Use COPY to load an existing relation.")
        );
    }
    ereport(
        ERROR,
        errcode(ERRCODE_DUPLICATE_TABLE),
        errmsg("relation \"%s\" already exists", create->relation->relname)
    );
}

void
chdb_create_from_url(CreateStmt* create, chdbCreateFromURL* from) {
    from->structure_url = take_url_option(create, CHDB_STRUCTURE_FROM);
    from->copy_url      = take_url_option(create, CHDB_COPY_FROM);

    if (from->structure_url && from->copy_url) {
        ereport(
            ERROR,
            errcode(ERRCODE_SYNTAX_ERROR),
            errmsg(
                "chdb: cannot combine option \"%s\" with option \"%s\"",
                CHDB_STRUCTURE_FROM,
                CHDB_COPY_FROM
            ),
            errdetail(
                "\"%s\" derives the columns from the URL it loads.", CHDB_COPY_FROM
            )
        );
    }

    /* Partitions, inherited tables, typed tables, and column lists define columns */
    bool has_columns = create->tableElts != NIL || create->inhRelations != NIL ||
                       create->partbound || create->ofTypename;

    if (from->structure_url && has_columns) {
        ereport(
            ERROR,
            errcode(ERRCODE_SYNTAX_ERROR),
            errmsg(
                "chdb: option \"%s\" requires a table that names no columns",
                CHDB_STRUCTURE_FROM
            ),
            errdetail(
                "A column list, an INHERITS clause, an OF type, or a partition each "
                "define columns."
            )
        );
    }
    if (from->copy_url && !has_columns) {
        from->structure_url = from->copy_url;
    }

    error_if_relation_exists(create);
}

List*
chdb_url_columns(chdbCopyContext* ctx) {
    List* columns = NIL;
    ListCell* lc;

    foreach (lc, chdb_describe(ctx)) {
        chdbDescribedColumn* described = lfirst(lc);
        const char* where              = psprintf("column \"%s\"", described->name);
        chc_type* parsed;
        chc_err err = {};

        if (chc_type_parse(
                described->type, strlen(described->type), &pgch_alloc, &parsed, &err
            ) != CHC_OK) {
            pgch_raise(&err, ERRCODE_FEATURE_NOT_SUPPORTED, NULL, where);
        }

        pgch_pg_type type = pgch_pg_type_for(parsed, where);

        /*
         * Tuple and Map name a pseudo type that no table column holds, so
         * convert them to text arrays of one or more dimensions
         */
        if (OidIsValid(type.typid) && !pgch_pg_type_is_column(type)) {
            const char* decl = "text[]";

            type.typid  = TEXTOID;
            type.typmod = -1;
            type.ndims++;
            for (int dim = 1; dim < type.ndims; dim++) {
                decl = psprintf("%s[]", decl);
            }
            ereport(
                NOTICE,
                errmsg(
                    "chdb: column \"%s\" of type \"%s\" converted to %s",
                    described->name,
                    described->type,
                    decl
                )
            );
        }

        /* Reject pseudo types because table columns cannot use them */
        if (!pgch_pg_type_is_column(type)) {
            ereport(
                ERROR,
                errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                errmsg(
                    "chdb: no Postgres type for column \"%s\" of type \"%s\"",
                    described->name,
                    described->type
                ),
                errhint("Use a \"structure\" option that maps the column to String.")
            );
        }

        ColumnDef* column =
            makeColumnDef(described->name, type.typid, type.typmod, InvalidOid);

        /* One PG array type spans every depth, so attndims keeps ClickHouse nesting */
        for (int dim = 0; dim < type.ndims; dim++) {
            column->typeName->arrayBounds =
                lappend(column->typeName->arrayBounds, makeInteger(-1));
        }

        /* Apply nullability reported by ClickHouse */
        column->is_not_null = !type.nullable;
        columns             = lappend(columns, column);
    }

    if (columns == NIL) {
        ereport(
            ERROR,
            errcode(ERRCODE_INVALID_PARAMETER_VALUE),
            errmsg("chdb: no columns found at \"%s\"", ctx->url)
        );
    }

    return columns;
}

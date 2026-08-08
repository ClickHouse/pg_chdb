/*
 * COPY between Postgres and chDB in ClickHouse's Native format. The one TU
 * defining the clickhouse-c and pg-clickhouse-c implementations.
 *
 * Values cross as Datums in both directions: a pgch_writer fed from scan slots
 * on the way out, a pgch_reader over the helper's output feeding an insert
 * loop on the way in. Nothing passes through COPY's text escaping, so arrays,
 * decimals and timestamps keep their types instead of collapsing to String.
 *
 * The insert loop mirrors CopyFrom in src/backend/commands/copyfrom.c, which
 * cannot be reused because its row source is its own text parser: triggers,
 * generated columns, constraints, partition routing, index maintenance and
 * multi-insert buffering are all replayed here.
 */

#include "postgres.h"

#include <string.h>

#include "access/heapam.h"
#include "access/htup_details.h"
#include "access/table.h"
#include "access/tableam.h"
#include "access/tupconvert.h"
#include "access/xact.h"
#include "catalog/pg_class.h"
#include "commands/trigger.h"
#include "executor/execPartition.h"
#include "executor/executor.h"
#include "executor/nodeModifyTable.h"
#include "foreign/fdwapi.h"
#include "miscadmin.h"
#include "optimizer/optimizer.h"
#include "rewrite/rewriteHandler.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/snapmgr.h"

#define CHC_IMPLEMENTATION
#define PGCH_IMPLEMENTATION
#include "clickhouse.h"

#include "pg-clickhouse-decode.h"
#include "pg-clickhouse-encode.h"

#include "native.h"

/*
 * Bytes to accumulate before cutting a block. ClickHouse coalesces small
 * blocks within one insert via min_insert_block_size_rows / _bytes, so the cut
 * only decides how much of the scan sits in memory.
 */
#define CHDB_NATIVE_BLOCK_BYTES (8 * 1024 * 1024)

/*
 * Buffer small writes before sending them to helper. Send writes at least as
 * large as direct-write limit without copying them into buffer first.
 */
#define CHDB_NATIVE_SINK_BYTES (256 * 1024)
#define CHDB_NATIVE_SINK_DIRECT (16 * 1024)

/* Rows and bytes to buffer before a table_multi_insert, as copyfrom.c does. */
#define CHDB_MAX_BUFFERED_TUPLES 1000
#define CHDB_MAX_BUFFERED_BYTES (64 * 1024)

/* ---- Postgres to chDB ------------------------------------------------ */

/*
 * Writer over the columns that `structure` declares. ClickHouse matches a Native
 * block's columns to the target by name and rejects one it cannot find, so the
 * block carries the declared names and types, not the relation's.
 *
 * A structure clause is a named Tuple's field list, so clickhouse-c's type
 * parser splits it: quoting, nesting and Enum8('a' = 1, 'b' = 2) come for free.
 * Children belong to the Tuple, which the writer's parent context outlives.
 */
static pgch_writer*
writer_for(const char* structure, int nattrs) {
    char* tuple = psprintf("Tuple(%s)", structure);
    chc_type* type;
    chc_err err = {};

    if (chc_type_parse(tuple, strlen(tuple), &pgch_alloc, &type, &err) != CHC_OK) {
        pgch_raise(&err, ERRCODE_INVALID_PARAMETER_VALUE, "structure: ");
    }

    size_t ncols   = chc_type_n_children(type);
    pgch_col* cols = palloc0(ncols * sizeof(pgch_col));

    for (size_t i = 0; i < ncols; i++) {
        cols[i].name = chc_type_tuple_field_name(type, i, &cols[i].name_len);
        cols[i].type = chc_type_child(type, i);

        /* A bare type parses as an unnamed field, leaving nothing to match on. */
        if (!cols[i].name) {
            ereport(
                ERROR,
                errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                errmsg("chdb: structure column %zu has no name", i + 1)
            );
        }
    }

    /* An append per attribute, so a mismatch would shift every column. */
    if (ncols != (size_t)nattrs) {
        ereport(
            ERROR,
            errcode(ERRCODE_INVALID_PARAMETER_VALUE),
            errmsg("chdb: structure declares %zu columns, copy has %d", ncols, nattrs)
        );
    }

    return pgch_writer_new(CurrentMemoryContext, cols, ncols);
}

/* Buffers small writes before sending them to helper. */
typedef struct nativeSink {
    chc_io io;
    chdbHelper* helper;
    size_t len;
    uint8_t buf[CHDB_NATIVE_SINK_BYTES];
} nativeSink;

static void
sink_flush(nativeSink* s) {
    if (s->len) {
        chdb_helper_write(s->helper, s->buf, s->len);
        s->len = 0;
    }
}

static int
sink_write(void* ud, const void* p, size_t len, chc_err* err pg_attribute_unused()) {
    nativeSink* s = ud;

    if (len >= CHDB_NATIVE_SINK_DIRECT) {
        sink_flush(s); /* send buffered bytes first */
        chdb_helper_write(s->helper, p, len);

        return CHC_OK;
    }

    if (s->len + len > sizeof(s->buf)) {
        sink_flush(s);
    }
    memcpy(s->buf + s->len, p, len);
    s->len += len;

    return CHC_OK;
}

static nativeSink*
sink_for(chdbHelper* helper) {
    nativeSink* s = palloc0(sizeof(*s));

    s->helper = helper;
    s->io     = (chc_io){ .ud = s, .write = sink_write };

    return s;
}

/*
 * Writes buffered rows to helper as one Native block. Sends data as encoder
 * produces it instead of copying entire block into another buffer first.
 */
static void
send_block(pgch_writer* w, nativeSink* sink) {
    chc_err err = {};

    if (chc_block_write(
            &sink->io, pgch_writer_build(w), &pgch_block_opts_local, &err
        ) != CHC_OK) {
        pgch_raise(&err, ERRCODE_EXTERNAL_ROUTINE_EXCEPTION, "block write: ");
    }
    pgch_writer_reset(w);
    sink_flush(sink);
}

/* table_beginscan gained a caller flags argument in PG 19. */
static inline TableScanDesc
begin_scan(Relation rel) {
#if PG_VERSION_NUM >= 190000
    return table_beginscan(rel, GetActiveSnapshot(), 0, NULL, 0);
#else
    return table_beginscan(rel, GetActiveSnapshot(), 0, NULL);
#endif
}

/* pgch_append_slot over `attnums` rather than every streamed attribute. */
static void
append_slot(pgch_writer* w, TupleTableSlot* slot, List* attnums) {
    TupleDesc desc = slot->tts_tupleDescriptor;
    size_t col     = 0;

    slot_getallattrs(slot);
    ListCell* lc;
    foreach (lc, attnums) {
        int i = lfirst_int(lc) - 1;

        pgch_append_datum(
            w,
            col++,
            slot->tts_values[i],
            TupleDescAttr(desc, i)->atttypid,
            slot->tts_isnull[i]
        );
    }
}

uint64_t
chdb_native_send(
    Relation rel,
    const char* structure,
    List* attnums,
    chdbHelper* helper
) {
    pgch_writer* w   = writer_for(structure, list_length(attnums));
    nativeSink* sink = sink_for(helper);
    MemoryContext rowcxt =
        AllocSetContextCreate(CurrentMemoryContext, "chdb row", ALLOCSET_DEFAULT_SIZES);
    TableScanDesc scan   = begin_scan(rel);
    TupleTableSlot* slot = table_slot_create(rel, NULL);
    uint64_t rows        = 0;

    /*
     * A NULL array has no ClickHouse representation, and a nullable array
     * column is ordinary in Postgres, so store the empty array rather than
     * failing the load on one.
     */
    pgch_writer_set_null_array(w, PGCH_NULL_ARRAY_EMPTY);

    while (table_scan_getnextslot(scan, ForwardScanDirection, slot)) {
        /* Appends copy into the writer's own context; detoasts land here. */
        MemoryContext oldcxt = MemoryContextSwitchTo(rowcxt);

        CHECK_FOR_INTERRUPTS();
        append_slot(w, slot, attnums);
        MemoryContextSwitchTo(oldcxt);
        MemoryContextReset(rowcxt);
        rows++;

        if (pgch_writer_bytes(w) >= CHDB_NATIVE_BLOCK_BYTES) {
            send_block(w, sink);
        }
    }

    /* Rows the scan left short of a cut, so one block, not one per row. */
    if (pgch_writer_rows(w)) {
        send_block(w, sink);
    }

    ExecDropSingleTupleTableSlot(slot);
    table_endscan(scan);
    pgch_writer_free(w);
    MemoryContextDelete(rowcxt);

    return rows;
}

/* ---- chDB to Postgres ------------------------------------------------ */

/*
 * Buffer small reads from helper. Read large chunks directly into destination,
 * so only block metadata usually passes through this buffer.
 */
#define CHDB_NATIVE_SOURCE_BYTES (256 * 1024)

/* Reads Native output from helper one block at a time. */
typedef struct nativeSource {
    chc_io io;
    chc_in* in;
    MemoryContext cxt; /* decoded blocks outlive rows read from them */
    chdbHelper* helper;
    char* error;
} nativeSource;

/* Helper failures are reported directly, so callback always returns success. */
static int
source_read(
    void* ud,
    void* buf,
    size_t len,
    size_t* got,
    chc_err* err pg_attribute_unused()
) {
    nativeSource* s = ud;

    *got = chdb_helper_recv(s->helper, buf, len);

    return CHC_OK;
}

/* Checks for interrupts before decoder refills input buffer. */
static int
source_cancelled(void* ud pg_attribute_unused()) {
    CHECK_FOR_INTERRUPTS();

    return 0;
}

static const chc_block*
source_next(void* ud) {
    nativeSource* s = ud;
    chc_block* block;
    chc_err err = {};

    if (s->error) {
        return NULL;
    }

    MemoryContext oldcxt = MemoryContextSwitchTo(s->cxt);

    /* NULL block without an error marks end of stream. */
    if (chc_block_read(s->in, &pgch_alloc, &pgch_block_opts_local, &block, &err) !=
        CHC_OK) {
        s->error = MemoryContextStrdup(
            s->cxt, err.msg[0] ? err.msg : "chDB block could not be read"
        );
        block = NULL;
    }
    MemoryContextSwitchTo(oldcxt);

    return block;
}

static const char*
source_error(void* ud) {
    return ((nativeSource*)ud)->error;
}

/* Creates block reader for helper output in current memory context. */
static pgch_block_source
source_for(chdbHelper* helper) {
    nativeSource* s = palloc0(sizeof(*s));
    chc_err err     = {};

    s->helper = helper;
    s->cxt    = CurrentMemoryContext;
    s->io = (chc_io){ .ud = s, .read = source_read, .check_cancel = source_cancelled };
    s->in = pgch_in_alloc();
    if (chc_in_init(s->in, &s->io, &pgch_alloc, CHDB_NATIVE_SOURCE_BYTES, &err) !=
        CHC_OK) {
        pgch_raise(&err, ERRCODE_EXTERNAL_ROUTINE_EXCEPTION, "reader init: ");
    }

    return (pgch_block_source){ .ud         = s,
                                .next_block = source_next,
                                .error      = source_error };
}

/*
 * Rows on their way into the relation, buffered when the target allows it.
 * copyfrom.c splits this across CopyMultiInsertInfo and CopyMultiInsertBuffer,
 * one buffer per partition; a single relation needs one of each.
 */
typedef struct nativeInsert {
    EState* estate;
    ResultRelInfo* target;
    TransitionCaptureState* transition;
    CommandId cid;
    int ti_options;
    BulkInsertState bistate;
    bool buffered; /* target takes table_multi_insert */
    int nused;
    size_t bytes;
    TupleTableSlot* slots[CHDB_MAX_BUFFERED_TUPLES];
} nativeInsert;

/* ExecInsertIndexTuples' argument order changed in PG 19. */
static inline List*
insert_index_tuples(ResultRelInfo* rri, TupleTableSlot* slot, EState* estate) {
#if PG_VERSION_NUM >= 190000
    return ExecInsertIndexTuples(rri, estate, 0, slot, NIL, NULL);
#else
    return ExecInsertIndexTuples(rri, slot, estate, false, false, NULL, NIL, false);
#endif
}

/* Index entries and AFTER ROW triggers for a tuple already in the table. */
static void
after_insert(nativeInsert* ins, ResultRelInfo* rri, TupleTableSlot* slot) {
    List* recheck =
        rri->ri_NumIndices > 0 ? insert_index_tuples(rri, slot, ins->estate) : NIL;

    ExecARInsertTriggers(ins->estate, rri, slot, recheck, ins->transition);
    list_free(recheck);
}

/* Writes the buffered rows out, as CopyMultiInsertBufferFlush does. */
static void
flush_buffer(nativeInsert* ins) {
    if (!ins->nused) {
        return;
    }

    /* table_multi_insert may leak, so give it a context that gets reset. */
    MemoryContext oldcxt = MemoryContextSwitchTo(GetPerTupleMemoryContext(ins->estate));

    table_multi_insert(
        ins->target->ri_RelationDesc,
        ins->slots,
        ins->nused,
        ins->cid,
        ins->ti_options,
        ins->bistate
    );
    MemoryContextSwitchTo(oldcxt);

    for (int i = 0; i < ins->nused; i++) {
        after_insert(ins, ins->target, ins->slots[i]);
        ExecClearTuple(ins->slots[i]);
    }

    ins->nused = 0;
    ins->bytes = 0;
}

/* Slot to build the next buffered row in. */
static TupleTableSlot*
buffer_slot(nativeInsert* ins) {
    if (!ins->slots[ins->nused]) {
        ins->slots[ins->nused] = table_slot_create(ins->target->ri_RelationDesc, NULL);
    }

    return ins->slots[ins->nused];
}

/* Stores the row `buffer_slot` handed out, flushing once the buffer is full. */
static void
buffer_store(nativeInsert* ins, TupleTableSlot* slot) {
    ins->bytes += heap_compute_data_size(
        slot->tts_tupleDescriptor, slot->tts_values, slot->tts_isnull
    );

    /* The values point into the per-row context, so the slot needs its own. */
    ExecMaterializeSlot(slot);
    ins->nused++;

    if (ins->nused >= CHDB_MAX_BUFFERED_TUPLES ||
        ins->bytes >= CHDB_MAX_BUFFERED_BYTES) {
        flush_buffer(ins);
    }
}

/*
 * One row into `rri`, the routed partition when there is one. False when an
 * FDW took the row and stored nothing, which counts as no row inserted.
 */
static bool
insert_row(nativeInsert* ins, ResultRelInfo* rri, TupleTableSlot* slot) {
    if (rri->ri_FdwRoutine) {
        slot = rri->ri_FdwRoutine->ExecForeignInsert(ins->estate, rri, slot, NULL);
        if (!slot) {
            return false; /* "do nothing" */
        }

        /* AFTER ROW triggers might reference the tableoid column. */
        slot->tts_tableOid = RelationGetRelid(rri->ri_RelationDesc);
        ExecARInsertTriggers(ins->estate, rri, slot, NIL, ins->transition);
        return true;
    }

    table_tuple_insert(
        rri->ri_RelationDesc, slot, ins->cid, ins->ti_options, ins->bistate
    );
    after_insert(ins, rri, slot);

    return true;
}

/*
 * Defaults for the columns a COPY column list leaves out, which BeginCopyFrom
 * prepares in copyfrom.c.
 */
typedef struct nativeDefaults {
    int n;
    int* dest; /* attribute offsets the defaults fill */
    ExprState** exprs;
} nativeDefaults;

static nativeDefaults
defaults_for(Relation rel, List* attnums) {
    TupleDesc desc          = RelationGetDescr(rel);
    nativeDefaults defaults = { .n     = 0,
                                .dest  = palloc(desc->natts * sizeof(int)),
                                .exprs = palloc(desc->natts * sizeof(ExprState*)) };

    for (int attnum = 1; attnum <= desc->natts; attnum++) {
        Form_pg_attribute attr = TupleDescAttr(desc, attnum - 1);

        /* ExecComputeStoredGenerated computes a generated column instead. */
        if (attr->attisdropped || attr->attgenerated ||
            list_member_int(attnums, attnum)) {
            continue;
        }
        Expr* expr = (Expr*)build_column_default(rel, attnum);
        if (!expr) {
            continue;
        }

        defaults.dest[defaults.n]    = attnum - 1;
        defaults.exprs[defaults.n++] = ExecInitExpr(expression_planner(expr), NULL);
    }

    return defaults;
}

/* Evaluates the defaults into `slot`, per row so a volatile one varies. */
static void
fill_defaults(const nativeDefaults* defaults, EState* estate, TupleTableSlot* slot) {
    if (!defaults->n) {
        return;
    }

    ExprContext* econtext = GetPerTupleExprContext(estate);
    MemoryContext oldcxt  = MemoryContextSwitchTo(econtext->ecxt_per_tuple_memory);
    for (int i = 0; i < defaults->n; i++) {
        slot->tts_values[defaults->dest[i]] = ExecEvalExpr(
            defaults->exprs[i], econtext, &slot->tts_isnull[defaults->dest[i]]
        );
    }
    MemoryContextSwitchTo(oldcxt);
}

/* Reader errors carry the chDB message; the query text is the caller's. */
pg_noreturn static void
report_reader_error(const char* error) {
    ereport(
        ERROR,
        errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
        errmsg("chdb: error fetching chDB query result"),
        errdetail("%s", error)
    );
}

/*
 * CopyFrom from src/backend/commands/copyfrom.c, NextCopyFrom replaced by
 * pgch_reader_next. The steps between the row source and table_tuple_insert are
 * that function's, in its order, so diff against it when a release moves the
 * insert path. Reader setup comes first, then markers bound the copied part.
 *
 * Not carried over: FREEZE and the new-in-transaction ti_options, the WHERE
 * filter, and on_error's soft-error retry. Defaults are evaluated per row, so
 * copyfrom.c's volatile_defexprs test has no analogue below.
 */
uint64_t
chdb_native_receive(
    Relation rel,
    List* attnums,
    List* rtable,
    List* rteperminfos,
    chdbHelper* helper
) {
    TupleDesc desc = RelationGetDescr(rel);
    /* Blocks and reader state live here, one row's values in rowcxt. */
    MemoryContext streamcxt = AllocSetContextCreate(
        CurrentMemoryContext, "chdb stream", ALLOCSET_DEFAULT_SIZES
    );
    MemoryContext rowcxt =
        AllocSetContextCreate(CurrentMemoryContext, "chdb row", ALLOCSET_DEFAULT_SIZES);
    MemoryContext oldcxt = MemoryContextSwitchTo(streamcxt);

    pgch_block_source src = source_for(helper);
    size_t ncols          = list_length(attnums);
    int* dest             = palloc(ncols * sizeof(int));
    size_t n              = 0;

    ListCell* lc;
    foreach (lc, attnums) {
        dest[n++] = lfirst_int(lc) - 1;
    }

    pgch_reader reader;
    pgch_reader_init(&reader, &src);
    if (reader.error) {
        report_reader_error(reader.error);
    }
    if (pgch_reader_columns(&reader) == 0) {
        /* Nothing streamed at all, so there is no schema to check. */
        MemoryContextSwitchTo(oldcxt);
        MemoryContextDelete(streamcxt);
        MemoryContextDelete(rowcxt);
        return 0;
    }
    if (pgch_reader_columns(&reader) != ncols) {
        ereport(
            ERROR,
            errcode(ERRCODE_BAD_COPY_FILE_FORMAT),
            errmsg(
                "chdb: chDB returned %zu columns, expected %zu",
                pgch_reader_columns(&reader),
                ncols
            )
        );
    }

    /* Conversion state per column, off the column type rather than a value. */
    void** states = palloc0(ncols * sizeof(void*));

    for (size_t i = 0; i < ncols; i++) {
        Form_pg_attribute attr = TupleDescAttr(desc, dest[i]);
        states[i] =
            pgch_reader_convert_init(&reader, i, attr->atttypid, attr->atttypmod);
    }

    MemoryContextSwitchTo(oldcxt);

    nativeDefaults defaults = defaults_for(rel, attnums);

    /* ---- from here on, copyfrom.c's CopyFrom ---- */

    /*
     * The executor wants a range table to make index entries against. It is
     * the one hook.c already built for `rel` and checked the copied columns
     * against, so the entry the insert runs under is the entry that passed.
     */
    EState* estate = CreateExecutorState();

#if PG_VERSION_NUM >= 180000
    ExecInitRangeTable(estate, rtable, rteperminfos, bms_make_singleton(1));
#else
    ExecInitRangeTable(estate, rtable, rteperminfos);
#endif
    ResultRelInfo* target = makeNode(ResultRelInfo);

    ExecInitResultRelation(estate, target, 1);
#if PG_VERSION_NUM >= 190000
    CheckValidResultRel(target, CMD_INSERT, ONCONFLICT_NONE, NIL, NULL);
#elif PG_VERSION_NUM >= 180000
    CheckValidResultRel(target, CMD_INSERT, ONCONFLICT_NONE, NIL);
#elif PG_VERSION_NUM >= 170000
    CheckValidResultRel(target, CMD_INSERT, NIL);
#else
    CheckValidResultRel(target, CMD_INSERT);
#endif
    ExecOpenIndices(target, false);

    /* A foreign table target initializes itself through a ModifyTableState. */
    ModifyTableState* mtstate = makeNode(ModifyTableState);

    mtstate->ps.plan           = NULL;
    mtstate->ps.state          = estate;
    mtstate->operation         = CMD_INSERT;
    mtstate->mt_nrels          = 1;
    mtstate->resultRelInfo     = target;
    mtstate->rootResultRelInfo = target;
    if (target->ri_FdwRoutine && target->ri_FdwRoutine->BeginForeignInsert) {
        target->ri_FdwRoutine->BeginForeignInsert(mtstate, target);
    }
    target->ri_BatchSize = 1;

    AfterTriggerBeginQuery();

    /* Partition routing wants to know whether transition tuples are captured. */
    nativeInsert ins = {};

    ins.transition = mtstate->mt_transition_capture =
        MakeTransitionCaptureState(rel->trigdesc, RelationGetRelid(rel), CMD_INSERT);

    PartitionTupleRouting* proute = NULL;

    if (rel->rd_rel->relkind == RELKIND_PARTITIONED_TABLE) {
        proute = ExecSetupPartitionTupleRouting(estate, rel);
    }

    bool before_row =
        target->ri_TrigDesc && target->ri_TrigDesc->trig_insert_before_row;
    bool instead_row =
        target->ri_TrigDesc && target->ri_TrigDesc->trig_insert_instead_row;

    /*
     * BEFORE and INSTEAD OF triggers may query the table, so rows they see
     * cannot sit in a buffer. Neither can a routed row: a buffer belongs to
     * one relation, and copyfrom.c's per-partition buffers are more machinery
     * than a first cut needs.
     */
    ins.estate     = estate;
    ins.target     = target;
    ins.cid        = GetCurrentCommandId(true);
    ins.ti_options = 0;
    ins.bistate    = GetBulkInsertState();
    ins.buffered   = !proute && !target->ri_FdwRoutine && !before_row && !instead_row;

    TupleTableSlot* rootslot = table_slot_create(rel, &estate->es_tupleTable);
    ResultRelInfo* routed    = NULL;
    uint64_t rows            = 0;

    ExecBSInsertTriggers(estate, target);

    for (;;) {
        CHECK_FOR_INTERRUPTS();
        ResetPerTupleExprContext(estate);
        MemoryContextReset(rowcxt);

        TupleTableSlot* slot = ins.buffered ? buffer_slot(&ins) : rootslot;
        ExecClearTuple(slot);
        /* Attributes without a stream column, default or generator stay null. */
        memset(slot->tts_isnull, true, desc->natts * sizeof(bool));

        /*
         * NextCopyFrom's place in CopyFrom. Values decode into rowcxt, but the
         * call crossing into the next block allocates that block too, and a
         * block outlives the row that pulled it in. Run that one call in
         * streamcxt and leave its row's values there: one row per block, not
         * one per row.
         */
        bool crossing = !reader.cur || reader.row >= chc_block_n_rows(reader.cur);

        MemoryContextSwitchTo(crossing ? streamcxt : rowcxt);
        if (!pgch_reader_next(&reader)) {
            MemoryContextSwitchTo(oldcxt);
            break;
        }
        pgch_reader_fill_map(&reader, states, dest, slot->tts_values, slot->tts_isnull);
        MemoryContextSwitchTo(oldcxt);
        fill_defaults(&defaults, estate, slot);
        ExecStoreVirtualTuple(slot);

        /* Constraints may reference the tableoid column. */
        slot->tts_tableOid = RelationGetRelid(rel);

        ResultRelInfo* rri = target;
        if (proute) {
            /* Raises when no partition of the row's key exists. */
            rri = ExecFindPartition(mtstate, target, proute, slot, estate);
            if (rri != routed) {
                before_row =
                    rri->ri_TrigDesc && rri->ri_TrigDesc->trig_insert_before_row;
                instead_row =
                    rri->ri_TrigDesc && rri->ri_TrigDesc->trig_insert_instead_row;
                ReleaseBulkInsertStatePin(ins.bistate);
                routed = rri;
            }

            /*
             * A BEFORE trigger on the partition can change the tuple, so only
             * an untriggered partition can hand its row to transition capture
             * unconverted.
             */
            if (ins.transition) {
                ins.transition->tcs_original_insert_tuple = before_row ? NULL : slot;
            }

            TupleConversionMap* map = ExecGetRootToChildMap(rri, estate);

            if (map) {
                slot = execute_attr_map_slot(
                    map->attrMap, slot, rri->ri_PartitionTupleSlot
                );
            }
            slot->tts_tableOid = RelationGetRelid(rri->ri_RelationDesc);
        }

        if (before_row && !ExecBRInsertTriggers(estate, rri, slot)) {
            continue; /* "do nothing" */
        }

        if (instead_row) {
            ExecIRInsertTriggers(estate, rri, slot);
        } else {
            if (rri->ri_RelationDesc->rd_att->constr &&
                rri->ri_RelationDesc->rd_att->constr->has_generated_stored) {
                ExecComputeStoredGenerated(rri, estate, slot, CMD_INSERT);
            }
            if (!rri->ri_FdwRoutine && rri->ri_RelationDesc->rd_att->constr) {
                ExecConstraints(rri, slot, estate);
            }

            /*
             * Routing already proved the partition constraint, unless a BEFORE
             * trigger has had the tuple since.
             */
            if (rri->ri_RelationDesc->rd_rel->relispartition &&
                (!proute || before_row)) {
                ExecPartitionCheck(rri, slot, estate, true);
            }

            if (ins.buffered) {
                buffer_store(&ins, slot);
            } else if (!insert_row(&ins, rri, slot)) {
                continue;
            }
        }

        rows++;
    }

    /* Ours: the loop ends on a reader error the same way it ends on no rows. */
    if (reader.error) {
        report_reader_error(reader.error);
    }

    flush_buffer(&ins);
    for (int i = 0; i < CHDB_MAX_BUFFERED_TUPLES && ins.slots[i]; i++) {
        ExecDropSingleTupleTableSlot(ins.slots[i]);
    }
    FreeBulkInsertState(ins.bistate);
    if (ins.buffered) {
        table_finish_bulk_insert(rel, ins.ti_options);
    }

    ExecASInsertTriggers(estate, target, ins.transition);
    AfterTriggerEndQuery(estate);
    ExecResetTupleTable(estate->es_tupleTable, false);

    if (target->ri_FdwRoutine && target->ri_FdwRoutine->EndForeignInsert) {
        target->ri_FdwRoutine->EndForeignInsert(estate, target);
    }
    if (proute) {
        ExecCleanupTupleRouting(mtstate, proute);
    }

    /* Closes the indices ExecOpenIndices opened. */
    ExecCloseResultRelations(estate);
    ExecCloseRangeTableRelations(estate);
    FreeExecutorState(estate);

    /* ---- end of CopyFrom ---- */

    MemoryContextDelete(streamcxt);
    MemoryContextDelete(rowcxt);

    return rows;
}

#ifndef CHDB_CREATE_H
#define CHDB_CREATE_H

#include "postgres.h"

#include "nodes/parsenodes.h"

#include "copy.h"

/* Option names for CREATE TABLE with URL input */
#define CHDB_STRUCTURE_FROM "structure_from"
#define CHDB_COPY_FROM "copy_from"

/* URLs used to infer columns and copy rows */
typedef struct chdbCreateFromURL {
    char* structure_url; /* URL used to infer columns, or NULL */
    char* copy_url;      /* URL used to copy rows, or NULL */
} chdbCreateFromURL;

/* Return true when `create` uses a URL for columns or rows */
extern bool
chdb_creates_from_url(CreateStmt* create);

/*
 * Move URL options from `create` to `from`, leave other options unchanged
 * Raise an error when statement cannot use URL options
 */
extern void
chdb_create_from_url(CreateStmt* create, chdbCreateFromURL* from);

/*
 * Return column definitions from `ctx` URL in source order
 */
extern List*
chdb_url_columns(chdbCopyContext* ctx);

#endif /* CHDB_CREATE_H */

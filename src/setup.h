#ifndef CHDB_SETUP_H
#define CHDB_SETUP_H

/* Where the backend hands the helper its setup payload. */
#define CHDB_SETUP_FD 3

/* Type of query we ask the helper to execute. */
typedef uint8_t chdbCmdType;
#define CHDB_CMD_SELECT 'S' /* SELECT, COPY FROM */
#define CHDB_CMD_INSERT 'I' /* COPY TO */

/* Contextual information for the helper. */
typedef struct chdbHelperContext {
    chdbCmdType cmd;      /* Type of query to execute. */
    uint16_t max_memory;  /* max_memory_usage setting in MB, 0 for none */
    uint16_t max_threads; /* max_threads setting, 0 for none */
    uint16_t max_parsers; /* max_parsing_threads setting, 0 for none */
} chdbHelperContext;

/*
 * The payload the backend writes to CHDB_SETUP_FD and then closes. The helper
 * reads it whole before touching either data channel.
 * Fields are native endian.
 *
 *   chdbHelperContext      command type, settings
 *   string                 query
 *   uint16                 parameter count
 *   string                 parameter name and value, repeated
 *
 * A string is a uint32 byte count followed by that many bytes, unterminated.
 */

/* Refuse a payload larger than this rather than sizing a buffer from it. */
#define CHDB_SETUP_MAX (16 * 1024 * 1024)

/* Exit status telling the backend execution broke rather than the query. */
#define CHDB_HELPER_LOST_BACKEND 2

#endif /* CHDB_SETUP_H */

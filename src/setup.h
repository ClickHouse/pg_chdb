#ifndef CHDB_SETUP_H
#define CHDB_SETUP_H

/* Where the backend hands the helper its setup payload. */
#define CHDB_SETUP_FD 3

/*
 * The payload the backend writes to CHDB_SETUP_FD and then closes. The helper
 * reads it whole before touching either data channel.
 * Fields are native endian.
 *
 *   uint8    1 for COPY FROM, 0 for COPY TO
 *   string   query
 *   uint16   parameter count
 *   string   parameter name and value, repeated
 *
 * A string is a uint32 byte count followed by that many bytes, unterminated.
 */

/* Refuse a payload larger than this rather than sizing a buffer from it. */
#define CHDB_SETUP_MAX (16 * 1024 * 1024)

/* Exit status telling the backend the copy broke rather than the query. */
#define CHDB_HELPER_LOST_BACKEND 2

#endif /* CHDB_SETUP_H */

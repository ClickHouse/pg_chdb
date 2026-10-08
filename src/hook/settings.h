#ifndef CHDB_HOOK_SETTINGS_H
#define CHDB_HOOK_SETTINGS_H

#include "postgres.h"

/*
 * Return the canonical ClickHouse name for a supported COPY option, or NULL
 * when `option` is not a format setting. The returned string has static
 * storage, except for canonical format_/input_format_/output_format_ names,
 * where it aliases `option`.
 */
extern const char*
chdb_format_setting_name(const char* option);

/* True when pg_chdb must retain control of the canonical setting. */
extern bool
chdb_format_setting_protected(const char* name);

#endif /* CHDB_HOOK_SETTINGS_H */

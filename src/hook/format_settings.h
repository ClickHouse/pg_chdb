#ifndef CHDB_HOOK_FORMAT_SETTINGS_H
#define CHDB_HOOK_FORMAT_SETTINGS_H

#include "postgres.h"

/* Return the canonical ClickHouse format setting name, or NULL if unsupported. */
extern const char*
chdb_format_setting_name(const char* option);

/* True when pg_chdb must retain control of the canonical setting. */
extern bool
chdb_format_setting_protected(const char* name);

#endif /* CHDB_HOOK_FORMAT_SETTINGS_H */

#ifndef CHDB_GUCS_H
#define CHDB_GUCS_H

/* Macro used to construct GUCs consistently for a namespace. */
#define CHDB_GUCS(ns)                                                                  \
    DefineCustomIntVariable(                                                           \
        ns ".max_memory",                                                              \
        "Memory budget for a chDB query.",                                             \
        "Zero leaves chDB to decide. Applied as max_memory_usage.",                    \
        &chdb_max_memory,                                                              \
        0,                                                                             \
        0,                                                                             \
        UINT16_MAX,                                                                    \
        PGC_SUSET,                                                                     \
        GUC_UNIT_MB,                                                                   \
        NULL,                                                                          \
        NULL,                                                                          \
        NULL                                                                           \
    );                                                                                 \
    DefineCustomIntVariable(                                                           \
        ns ".max_threads",                                                             \
        "Thread budget for a chDB query.",                                             \
        "Zero leaves chDB to decide. Applied as max_threads.",                         \
        &chdb_max_threads,                                                             \
        0,                                                                             \
        0,                                                                             \
        UINT16_MAX,                                                                    \
        PGC_SUSET,                                                                     \
        0,                                                                             \
        NULL,                                                                          \
        NULL,                                                                          \
        NULL                                                                           \
    );                                                                                 \
    DefineCustomIntVariable(                                                           \
        ns ".max_parsing_threads",                                                     \
        "Thread budget for parallel data parsing in a chDB query.",                    \
        "Zero leaves chDB to decide. Applied as max_parsing_threads.",                 \
        &chdb_max_parsers,                                                             \
        0,                                                                             \
        0,                                                                             \
        UINT16_MAX,                                                                    \
        PGC_SUSET,                                                                     \
        0,                                                                             \
        NULL,                                                                          \
        NULL,                                                                          \
        NULL                                                                           \
    );                                                                                 \
    MarkGUCPrefixReserved(ns);

#endif /* CHDB_GUCS_H */

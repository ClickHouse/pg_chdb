MODULE_big   = chdb_bgw
OBJS 		 = $(subst .c,.o, $(wildcard *.c))
PGCH_DIR     = ../../vendor/pg-clickhouse-c
CH_C_DIR     = $(PGCH_DIR)/clickhouse-c
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror
# -isystem keeps the vendored headers' warnings out of the -Werror build.
# PGCH_MSG_PREFIX prefixes messages pg-clickhouse-c raises like our own.
PG_CPPFLAGS  = -isystem $(CH_C_DIR) -isystem $(PGCH_DIR) -DPGCH_MSG_PREFIX='"chdb: "'
PG_LDFLAGS   = -lchdb
PG_CONFIG   ?= pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# PGXS tracks no header dependencies, and the vendored libraries are all header.
$(OBJS): $(wildcard *.h $(PGCH_DIR)/*.h $(CH_C_DIR)/*.h)

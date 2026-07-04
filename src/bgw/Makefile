MODULE_big = chdb_bgw
OBJS = $(subst .c,.o, $(wildcard *.c))
PG_CONFIG ?= pg_config
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

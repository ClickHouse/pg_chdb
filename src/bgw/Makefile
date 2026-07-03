MODULE_big = chdb_bgw
OBJS = $(subst .c,.o, $(wildcard *.c))
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror

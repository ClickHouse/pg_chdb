MODULE_big   = chdb_bgw
OBJS 		 = $(subst .c,.o, $(wildcard *.c))
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror
PG_LDFLAGS   = -lchdb
PG_CONFIG   ?= pg_config

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

PROGRAM  = chdb_helper
OBJS     = $(PROGRAM).o
# override, so a CFLAGS on the command line adds to the project flags.
override CFLAGS  += -Wall -Werror -O2
override LDLIBS  += -lchdb

ifneq ($(LIBCHDB_DIR),)
override LDFLAGS += -L../../$(LIBCHDB_DIR)/lib
override CFLAGS  += -I../../$(LIBCHDB_DIR)/include
endif

all: $(PROGRAM)

$(OBJS): chdb_helper.c ../setup.h

.PHONY: clean
clean:
	rm -f $(PROGRAM) $(OBJS)

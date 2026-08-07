PROGRAM  = chdb_helper
OBJS     = chdb_helper.o
# override, so a CFLAGS on the command line adds to the project flags.
override CFLAGS  += -Wall -Werror -O2
override LDLIBS  += -lchdb

all: $(PROGRAM)

$(OBJS): chdb_helper.c ../setup.h

.PHONY: clean
clean:
	rm -f $(PROGRAM) $(OBJS)

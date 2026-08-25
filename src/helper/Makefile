PROGRAM  = chdb_helper
OBJS     = $(PROGRAM).o
# override, so a CFLAGS on the command line adds to the project flags.
override CFLAGS  += -Wall -Werror -O2

ifneq ($(LIBCHDB_DIR),)
    override LIBCHDB_DIR := ../../$(LIBCHDB_DIR)
    override LDFLAGS += -L$(LIBCHDB_DIR)/lib
    override CFLAGS  += -I$(LIBCHDB_DIR)/include
else
    # Default location for chDB library releases.
    override LIBCHDB_DIR := /usr/local
endif

ifneq ($(LIBCHDB_BUILD),static)
    # Link the dynamic library.
    override LDLIBS  += -lchdb
else
    # Static compilation requires extra flags. See the Go builds for details:
    # https://github.com/chdb-io/chdb-core/tree/main/chdb/build/go-example
    OS = $(shell uname -s)
	STATIC_LIB = $(LIBCHDB_DIR)/lib/libchdb.a
    ifeq ($(OS),Linux)
        override LDFLAGS += -Wl,--whole-archive $(STATIC_LIB) -Wl,--no-whole-archive -lm -lrt -lpthread -ldl
    else ifeq ($(OS),Darwin)
        override LDFLAGS += -mmacosx-version-min=10.15 -Wl,-force_load,$(STATIC_LIB) -liconv -framework CoreFoundation -framework Security
    else
        $(error Unsupported OS "$(OS)": libchdb supports only Linux and macOS)
    endif
endif

all: $(PROGRAM)

$(OBJS): chdb_helper.c ../setup.h

.PHONY: clean
clean:
	rm -f $(PROGRAM) $(OBJS)

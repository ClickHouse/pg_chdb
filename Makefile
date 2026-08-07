EXTENSION    = $(shell grep -m 1 '"name":' META.json | \
               sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')
EXTVERSION   = $(shell grep -m 1 'default_version' chdb.control | \
               sed -e "s/[[:space:]]*default_version[[:space:]]*=[[:space:]]*'\([^']*\)',\{0,1\}/\1/")
DISTVERSION  = $(shell grep -m 1 '^[[:space:]]\{2\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')

MAX_CONCURRENT_TESTS ?= 6

# Header-only dependencies, vendored as submodules. clickhouse-c comes from
# pg-clickhouse-c's own pin, its signatures naming clickhouse-c types, so a
# second checkout on the include path would silently win.
PGCH_DIR     = $(CURDIR)/vendor/pg-clickhouse-c
CH_C_DIR     = $(PGCH_DIR)/clickhouse-c

DATA         = $(sort $(wildcard sql/$(EXTENSION)--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql)
DOCS         = $(wildcard doc/*.md)
TESTS        ?= $(wildcard test/sql/*.sql)
REGRESS      = --schedule test/schedule
REGRESS_OPTS = --inputdir=test --load-extension=$(EXTENSION) --max-concurrent-tests $(MAX_CONCURRENT_TESTS)
MODULE_big   = $(EXTENSION)
PG_CONFIG   ?= pg_config
TAP_TESTS   ?= 1

CLANG_FORMAT ?= clang-format

# Collect all the C files to compile into MODULE_big.
OBJS = $(subst .c,.o, $(wildcard src/*.c))

# Suppress annoying pre-c99 warning, error on other warnings.
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror

# -isystem keeps the vendored headers' warnings out of the -Werror build.
# PGCH_MSG_PREFIX prefixes messages pg-clickhouse-c raises like our own.
# clickhouse-c copies what it raises through chc_err.msg, 256 bytes by default,
# which clips the longer type names out of a decoding error.
PG_CPPFLAGS  = -isystem $(CH_C_DIR) -isystem $(PGCH_DIR) -DPGCH_MSG_PREFIX='"chdb: "' \
               -DCHC_ERR_MSG_LEN=4096

# Clean up generated files.
EXTRA_CLEAN  = src/version.h sql/$(EXTENSION)--$(EXTVERSION).sql src/helper/chdb_helper src/helper/*.o test/schedule

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Set default prove flags.
ifeq ($(PROVE_FLAGS),)
PROVE_FLAGS = -fwvj $(shell nproc)
endif

# Require the versioned SQL script.
all: sql/$(EXTENSION)--$(EXTVERSION).sql src/helper/chdb_helper

# PGXS tracks no header dependencies, and the vendored libraries are all header.
# *.bc compiles same sources, so needs same headers.
$(OBJS) $(OBJS:.o=.bc): $(CH_C_DIR)/clickhouse.h src/version.h \
                        $(wildcard src/*.h $(PGCH_DIR)/*.h $(CH_C_DIR)/*.h)

# Versioned SQL script.
sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

# Versioned source file.
src/version.h: META.json
	@printf '#define PGCHCB_VERSION "%s"\n' "$(DISTVERSION)" > $@

# Fail with something more useful than a missing include.
$(CH_C_DIR)/clickhouse.h: .gitmodules
	git submodule update --init --recursive

# The only program linking libchdb, kept beside the library that starts it.
src/helper/chdb_helper: $(wildcard src/helper/*.c) src/setup.h
	@$(MAKE) -C $(dir $@) all

# Install the helper. Write beside the live copy and rename over it: install
# unlinks its target first, so a COPY starting in that moment finds no helper.
# rename leaves no such gap.
install-helper: src/helper/chdb_helper
	@to=$(DESTDIR)$(pkglibdir)/chdb_helper; \
	  $(INSTALL_PROGRAM) $< $$to.new && mv -f $$to.new $$to
uninstall-helper:
	rm -f $(DESTDIR)$(pkglibdir)/chdb_helper
install: install-helper
uninstall: uninstall-helper

.PHONY: test/schedule # Depends on $(TESTS), so always rebuild.
test/schedule:
	@perl -E 'say "test: ", join " ", splice @ARGV, 0, $(MAX_CONCURRENT_TESTS) while @ARGV' $(patsubst test/sql/%.sql,%,$(TESTS)) > $@

installcheck: test/schedule

.PHONY: format # Format .c and .h files to project standard in .clang-format.
format: $(wildcard src/*.c src/*.h src/helper/*.c)
	@$(CLANG_FORMAT) --style=file:.clang-format -i $^

.PHONY: clang-tidy # Run clang-tidy static analysis (requires compile_commands.json)
clang-tidy: compile_commands.json
	run-clang-tidy -p . $(wildcard src/*.c src/*.h src/helper/*.c)

.PHONY: lint # Lint the project
lint: .pre-commit-config.yaml
	@pre-commit run --show-diff-on-failure --color=always --all-files

## .git/hooks/pre-commit: Install the pre-commit hook
.git/hooks/pre-commit:
	@printf "#!/bin/sh\nmake lint\n" > $@
	@chmod +x $@

# Requires https://github.com/rizsotto/Bear.
compile_commands.json:
	$(MAKE) clean -j $$(nproc)
	bear --config "bear.$$(if [ "$$(bear --version | awk -F'[^0-9]+' '{ print $$2 }')" -eq 3 ]; then echo 'json'; else echo 'yml'; fi)" -- $(MAKE) all -j $$(nproc)

debian-install-lint:
	@curl -SsLo /tmp/pre-commit.pyz https://github.com/pre-commit/pre-commit/releases/download/v4.6.0/pre-commit-4.6.0.pyz
	@printf "#!/bin/sh\npython3 /tmp/pre-commit.pyz \"\$$@\"\n" > /usr/local/bin/pre-commit
	@chmod +x /usr/local/bin/pre-commit

# Test the PGXN distribution.
dist-test: $(EXTENSION)-$(DISTVERSION).zip
	unzip $(EXTENSION)-$(DISTVERSION).zip
	cd $(EXTENSION)-$(DISTVERSION)
	make && make install && make installcheck

.PHONY: release-notes # Show release notes for current version (must have `mknotes` in PATH).
release-notes: CHANGELOG.md
	mknotes -v v$(DISTVERSION) -f $< -r https://github.com/$(or $(GITHUB_REPOSITORY),ClickHouse/pg_chdb)

$(EXTENSION)-$(DISTVERSION).zip:
	git archive-all -v --prefix "$(EXTENSION)-$(DISTVERSION)/" --force-submodules $(EXTENSION)-$(DISTVERSION).zip

# Run make print-VARIABLE_NAME to print VARIABLE_NAME's flavor and value.
print-%	: ; $(info $* is $(flavor $*) variable set to "$($*)") @true

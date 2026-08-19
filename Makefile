EXTENSION    = $(patsubst %.control,%,$(wildcard *.control))
EXTVERSION   = $(shell grep -m 1 'default_version' chdb.control | \
               sed -e "s/[[:space:]]*default_version[[:space:]]*=[[:space:]]*'\([^']*\)',\{0,1\}/\1/")
DISTVERSION  = $(shell grep -m 1 '^[[:space:]]\{2\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')

DATA         = $(sort $(wildcard sql/$(EXTENSION)--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql)
DOCS         = $(wildcard doc/*.md)
TESTS        ?= $(wildcard test/sql/*.sql)
REGRESS      = --schedule test/schedule
REGRESS_OPTS = --inputdir=test --load-extension=$(EXTENSION)
MODULE_big   = $(EXTENSION)
PG_CONFIG   ?= pg_config
TAP_TESTS   ?= 1
OBJS 		 = $(subst .c,.o, $(wildcard src/*.c))

CLANG_FORMAT ?= clang-format

# Version of libchdb to bundle.
LIBCHDB_VERSION = v26.7.0

# Header-only dependencies, vendored as submodules. clickhouse-c comes from
# pg-clickhouse-c's own pin, its signatures naming clickhouse-c types, so a
# second checkout on the include path would silently win.
PGCH_DIR     = $(CURDIR)/vendor/pg-clickhouse-c
CH_C_DIR     = $(PGCH_DIR)/clickhouse-c

# Downloaded copy of libchdb.
LIBCHDB_DIR = vendor/libchdb

# Suppress annoying pre-c99 warning, error on 	/other warnings.
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror

# -isystem keeps the vendored headers' warnings out of the -Werror build.
# PGCH_MSG_PREFIX prefixes messages pg-clickhouse-c raises like our own.
# clickhouse-c copies what it raises through chc_err.msg, 256 bytes by default,
# which clips the longer type names out of a decoding error.
PG_CPPFLAGS  = -isystem $(CH_C_DIR) -isystem $(PGCH_DIR) -DPGCH_MSG_PREFIX='"chdb: "' \
               -DCHC_ERR_MSG_LEN=4096

# Clean up generated files.
EXTRA_CLEAN  = src/version.h sql/$(EXTENSION)--$(EXTVERSION).sql src/hook/chdb_hook$(DLSUFFIX) src/hook/*.o src/hook/*.bc src/helper/chdb_helper src/helper/*.o test/schedule

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Set default prove flags.
ifeq ($(PROVE_FLAGS),)
PROVE_FLAGS = -fwvj $(shell nproc)
endif

# Build against, install, uninstall a local copy of libchdb.
ifneq ($(BUNDLE_LIBCHDB),)
OS         ?= $(shell uname -s | tr A-Z a-z)
ARCH        = $(shell uname -m)
LIBCHDB_DIR = vendor/libchdb-$(OS)-$(ARCH)
src/helper/chdb_helper: $(LIBCHDB_DIR)/lib/libchdb.so
install: install-libchdb
uninstall: uninstall-libchdb
endif

# Require the versioned SQL script.
all: sql/$(EXTENSION)--$(EXTVERSION).sql src/helper/chdb_helper src/hook/chdb_hook$(DLSUFFIX)

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

# Hook module.
HOOK_MODULE := src/hook/chdb_hook$(DLSUFFIX)
$(HOOK_MODULE): $(wildcard src/hook/*.c src/hook/*.h) $(OBJS)
	@$(MAKE) -C $(dir $@) all -j $$(nproc) CH_C_DIR=$(CH_C_DIR) PGCH_DIR=$(PGCH_DIR)

# Install and uninstall the chdb_hook module.
install-hook: $(HOOK_MODULE)
	$(INSTALL_SHLIB) $< '$(DESTDIR)$(pkglibdir)/'
uninstall-hook:
	rm -f $(DESTDIR)$(pkglibdir)/$(HOOK_MODULE)
install: install-hook
uninstall: uninstall-hook

# Fail with something more useful than a missing include.
$(CH_C_DIR)/clickhouse.h: .gitmodules
	git submodule update --init --recursive

# The only program linking libchdb, kept beside the library that starts it.
src/helper/chdb_helper: $(wildcard src/helper/*.c) src/setup.h
	@$(MAKE) -C $(dir $@) all LIBCHDB_DIR=$(LIBCHDB_DIR)

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
test/schedule: schedule = $(if $(TESTS),test: $(patsubst test/sql/%.sql,%,$(TESTS)),)
test/schedule:
	@echo $(schedule) > $@

installcheck: test/schedule

# libchdb
$(LIBCHDB_DIR)/lib/libchdb.so: vendor/get-libchdb.sh
	@env INSTALL_VERSION="$(LIBCHDB_VERSION)" DESTDIR=$(LIBCHDB_DIR) bash vendor/get-libchdb.sh

$(LIBCHDB_DIR)/lib/libchdb.a: vendor/get-libchdb.sh
	env INSTALL_VERSION="$(LIBCHDB_VERSION)" DESTDIR=$(LIBCHDB_DIR) STATIC=1 bash vendor/get-libchdb.sh

# GitHub stuff.
libchdb-version:
	@echo $(LIBCHDB_VERSION)
libchdb-variables:
	@echo VERSION=$(LIBCHDB_VERSION)
	@echo DIRECTORY=$(LIBCHDB_DIR)

# Install and uninstall libchdb, which is configured to live in /usr/local/lib.
install-libchdb: $(LIBCHDB_DIR)/lib/libchdb.so
	$(MKDIR_P) $(DESTDIR)/usr/local/lib
	$(INSTALL_SHLIB) $< $(DESTDIR)/usr/local/lib
	if [ "$$(uname -s)" = "Linux" ]; then ldconfig; fi
uninstall-libchdb:
	rm -f $(DESTDIR)/usr/local/lib/libchdb.so

.PHONY: format # Format .c and .h files to project standard in .clang-format.
format: $(wildcard src/*.c src/*.h src/helper/*.c)
	@$(CLANG_FORMAT) --style=file:.clang-format -i $^

.PHONY: type-table # Regenerate the chDB to Postgres table of doc/chdb_hook.md.
type-table:
	@(cd $(PGCH_DIR) && ./gen_type_table.awk) | dev/type_table.awk doc/chdb_hook.md

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
	bear --config "dev/bear.$$(if [ "$$(bear --version | awk -F'[^0-9]+' '{ print $$2 }')" -eq 3 ]; then echo 'json'; else echo 'yml'; fi)" -- $(MAKE) all -j $$(nproc)

debian-install-lint:
	@curl -SsLo /tmp/pre-commit.pyz https://github.com/pre-commit/pre-commit/releases/download/v4.6.0/pre-commit-4.6.0.pyz
	@printf "#!/bin/sh\npython3 /tmp/pre-commit.pyz \"\$$@\"\n" > /usr/local/bin/pre-commit
	@chmod +x /usr/local/bin/pre-commit

# Test the PGXN distribution.
dist-test: $(EXTENSION)-$(DISTVERSION).zip
	unzip $(EXTENSION)-$(DISTVERSION).zip
	cd $(EXTENSION)-$(DISTVERSION)
	$(MAKE) && $(MAKE) install && $(MAKE) installcheck

.PHONY: release-notes # Show release notes for current version (must have `mknotes` in PATH).
release-notes: CHANGELOG.md
	mknotes -v v$(DISTVERSION) -f $< -r https://github.com/$(or $(GITHUB_REPOSITORY),ClickHouse/pg_chdb)

$(EXTENSION)-$(DISTVERSION).zip:
	git archive-all -v --prefix "$(EXTENSION)-$(DISTVERSION)/" --force-submodules $(EXTENSION)-$(DISTVERSION).zip

# Run make print-VARIABLE_NAME to print VARIABLE_NAME's flavor and value.
print-%	: ; $(info $* is $(flavor $*) variable set to "$($*)") @true

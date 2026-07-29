EXTENSION    = $(shell grep -m 1 '"name":' META.json | \
               sed -e 's/[[:space:]]*"name":[[:space:]]*"\([^"]*\)",/\1/')
EXTVERSION   = $(shell grep -m 1 'default_version' chdb.control | \
               sed -e "s/[[:space:]]*default_version[[:space:]]*=[[:space:]]*'\([^']*\)',\{0,1\}/\1/")
DISTVERSION  = $(shell grep -m 1 '^[[:space:]]\{2\}"version":' META.json | \
               sed -e 's/[[:space:]]*"version":[[:space:]]*"\([^"]*\)",\{0,1\}/\1/')

MAX_CONCURRENT_TESTS ?= 8
DATA         = $(sort $(wildcard sql/$(EXTENSION)--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql)
DOCS         = $(wildcard doc/*.md)
TESTS        ?= $(wildcard test/sql/*.sql)
REGRESS      = --schedule test/schedule
REGRESS_OPTS = --inputdir=test --load-extension=$(EXTENSION) --max-concurrent-tests $(MAX_CONCURRENT_TESTS)
MODULE_big   = $(EXTENSION)
PG_CONFIG   ?= pg_config
TAP_TESTS   ?= 1

# Collect all the C files to compile into MODULE_big.
OBJS = $(subst .c,.o, $(wildcard src/*.c))

# Suppress annoying pre-c99 warning, error on other warnings.
PG_CFLAGS    = -Wno-declaration-after-statement -Wall -Werror

# Clean up generated files.
EXTRA_CLEAN  = src/version.h sql/$(EXTENSION)--$(EXTVERSION).sql src/bgw/chdb_bgw.* src/bgw/worker.o src/bgw/worker.bc test/schedule

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

ifeq ($(shell test $(VERSION_NUM) -lt 190000 && echo yes),yes)
TESTS := $(filter-out test/sql/oid8.sql,$(TESTS))
endif

# Set default prove flags.
ifeq ($(PROVE_FLAGS),)
PROVE_FLAGS = -fwj $(shell nproc)
endif

# Require the versioned SQL script.
all: sql/$(EXTENSION)--$(EXTVERSION).sql src/bgw/chdb_bgw$(DLSUFFIX)

# Require the version header.
$(OBJS): src/version.h

# Versioned SQL script.
sql/$(EXTENSION)--$(EXTVERSION).sql: sql/$(EXTENSION).sql
	cp $< $@

# Versioned source file.
src/version.h: META.json
	@printf '#define PGCHCB_VERSION "%s"\n' "$(DISTVERSION)" > $@

# Background worker.
src/bgw/chdb_bgw$(DLSUFFIX): $(wildcard src/bgw/*.c)
	@$(MAKE) -C $(dir $@) all -j $$(nproc)

# Install the chdb_bgw library.
install-bgw: src/bgw/chdb_bgw$(DLSUFFIX)
	cp -a $< $(DESTDIR)$(pkglibdir)/
uninstall-bgw:
	rm -f $(DESTDIR)$(pkglibdir)/src/bgw/chdb_bgw$(DLSUFFIX)
install: install-bgw
uninstall: uninstall-bgw

.PHONY: test/schedule # Depends on $(TESTS), so always rebuild.
test/schedule:
	@perl -E 'say "test: ", join " ", splice @ARGV, 0, $(MAX_CONCURRENT_TESTS) while @ARGV' $(patsubst test/sql/%.sql,%,$(TESTS)) > $@

installcheck: test/schedule

.PHONY: format # Format .c and .h files to project standard in .clang-format.
format: $(wildcard src/*.c src/*.h src/bgw/*.c src/bgw/*.h)
	@clang-format --style=file:.clang-format -i $^

.PHONY: clang-tidy # Run clang-tidy static analysis (requires compile_commands.json)
clang-tidy: compile_commands.json
	run-clang-tidy -p . $(wildcard src/*.c src/*.h src/bgw/*.c src/bgw/*.h)

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

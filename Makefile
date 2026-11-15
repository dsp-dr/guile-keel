.RECIPEPREFIX = >
.PHONY: all build test unit frames-diff trials clean tools
# Prefer a Guile 3 binary under any of its usual names; GUILE=... overrides.
GUILE ?= $(shell command -v guile3 2>/dev/null || command -v guile-3.0 2>/dev/null || command -v guile 2>/dev/null || echo guile)
GFORTH ?= gforth
FORTH_KEEL ?= ../../aygp-dr/forth-keel
SRC := src/keel/cell.scm src/keel/vm.scm src/keel/outer.scm
GO := $(SRC:src/%.scm=build/%.go)
# bin/keel and tests/frames-diff.sh read these, so one setting drives everything.
export GUILE
export GFORTH

all: test

build: $(GO)

build/%.go: src/%.scm
> @mkdir -p $(dir $@)
> @$(GUILE) -L src -C build -c "(use-modules (system base compile)) (compile-file \"$<\" #:output-file \"$(abspath $@)\")" > /dev/null

test: build unit frames-diff

# --fresh-auto-compile is not optional. The suites are auto-compiled into
# ~/.cache/guile/ccache keyed by their own path and mtime, and the modules
# export define-inlinable procedures (mem@, push!, pop!, rpush!, rpop!) whose
# bodies are inlined into that cached bytecode. Edit a module, leave a suite
# untouched, and the stale cache runs the previous version of every inlined
# guard. Mutation testing caught this: a deleted return-stack underflow check
# passed the suites with the cache warm and failed them without it.
GUILE_TEST_FLAGS ?= --fresh-auto-compile

unit:
> @cd tests && for t in cell-test vm-test outer-test; do $(GUILE) $(GUILE_TEST_FLAGS) -L ../src -C ../build $$t.scm > /dev/null 2>&1 || { echo "FAIL $$t"; $(GUILE) $(GUILE_TEST_FLAGS) -L ../src -C ../build $$t.scm 2>&1 | grep -E "FAIL|fail|ERROR" | head; exit 1; }; echo "PASS $$t"; done; rm -f *.log

frames-diff:
> @tests/frames-diff.sh

trials:
> @$(FORTH_KEEL)/sea-trials/run.sh --impl '$(CURDIR)/bin/keel {}' --layer 0

clean:
> rm -rf build

tools:
> @printf '%-8s %s\n' GUILE  "$(GUILE)"  "" "$$($(GUILE) --version 2>&1 | head -1)"
> @printf '%-8s %s\n' GFORTH "$(GFORTH)" "" "$$($(GFORTH) --version 2>&1 | head -1 || echo 'not found')"
> @printf '%-8s %s\n' TRIALS "$(FORTH_KEEL)"

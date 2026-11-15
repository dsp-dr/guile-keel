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

unit:
> @cd tests && for t in cell-test vm-test outer-test; do $(GUILE) -L ../src -C ../build $$t.scm > /dev/null 2>&1 || { echo "FAIL $$t"; $(GUILE) -L ../src -C ../build $$t.scm 2>&1 | grep -E "FAIL|fail|ERROR" | head; exit 1; }; echo "PASS $$t"; done; rm -f *.log

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

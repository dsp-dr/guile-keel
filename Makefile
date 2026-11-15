.RECIPEPREFIX = >
.PHONY: all build test unit frames-diff trials clean
GUILE ?= guile
GFORTH ?= gforth
FORTH_KEEL ?= ../../aygp-dr/forth-keel
SRC := src/keel/cell.scm src/keel/vm.scm src/keel/outer.scm
GO := $(SRC:src/%.scm=build/%.go)

all: test

build: $(GO)

build/%.go: src/%.scm
> @mkdir -p $(dir $@)
> @$(GUILE) -L src -C build -c "(use-modules (system base compile)) (compile-file \"$<\" #:output-file \"$(abspath $@)\")" > /dev/null

test: build unit frames-diff

unit:
> @cd tests && for t in cell-test vm-test outer-test; do guile -L ../src -C ../build $$t.scm > /dev/null 2>&1 || { echo "FAIL $$t"; guile -L ../src -C ../build $$t.scm 2>&1 | grep -E "FAIL|fail|ERROR" | head; exit 1; }; echo "PASS $$t"; done; rm -f *.log

frames-diff:
> @tests/frames-diff.sh

trials:
> @$(FORTH_KEEL)/sea-trials/run.sh --impl '$(CURDIR)/bin/keel {}' --layer 0

clean:
> rm -rf build

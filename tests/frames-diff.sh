#!/usr/bin/env bash
# Run tests/frames-check.fs on gforth and on keel; the outputs must be identical.
# GFORTH and KEEL select the two implementations; the Makefile exports GFORTH.
set -u
cd "$(dirname "$0")/.."
GFORTH=${GFORTH:-gforth}
KEEL=${KEEL:-bin/keel}

if ! command -v "$GFORTH" > /dev/null 2>&1; then
  echo "FAIL frames-diff ($GFORTH not on PATH: install gforth, or set GFORTH=...)" >&2
  exit 1
fi

tmp=$(mktemp) || exit 1
trap 'rm -f "$tmp"' EXIT

expected=$("$GFORTH" tests/frames-check.fs -e bye 2>&1)
actual=$("$KEEL" tests/frames-check.fs 2>&1)
if diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") > "$tmp"; then
  echo "PASS frames-diff ($(printf '%s\n' "$expected" | wc -l | tr -d ' ') lines identical to gforth)"
else
  echo "FAIL frames-diff"; head -20 "$tmp"; exit 1
fi

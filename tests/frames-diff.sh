#!/usr/bin/env bash
# Run tests/frames-check.fs on gforth and on keel; the outputs must be identical.
set -u
cd "$(dirname "$0")/.."
expected=$(gforth tests/frames-check.fs -e bye 2>&1)
actual=$(bin/keel tests/frames-check.fs 2>&1)
if diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") > /tmp/frames-diff.$$; then
  echo "PASS frames-diff ($(printf '%s\n' "$expected" | wc -l) lines identical to gforth)"; rm -f /tmp/frames-diff.$$
else
  echo "FAIL frames-diff"; head -20 /tmp/frames-diff.$$; rm -f /tmp/frames-diff.$$; exit 1
fi

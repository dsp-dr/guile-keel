#!/usr/bin/env bash
# ci-record.sh JOB LOG OUT: turn one CI job's output into a JSON record.
#
# The numbers come from what the suites printed in LOG, never from the README,
# so a record cannot claim more than the run showed. Unknown fields are null.
# Plain bash and sed so it runs in the FreeBSD VM too (no jq needed here).
set -u
job=$1 log=$2 out=$3

num() { sed -n "$1" "$log" | tail -1; }       # first capture of a sed -n s///p
cnt() { grep -c -E "$1" "$log" || true; }
js()  { if [ -n "${1-}" ]; then printf '%s' "$1"; else printf null; fi; }
str() { if [ -n "${1-}" ]; then printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"; else printf null; fi; }

# Same search as the Makefile: FreeBSD's package installs guile3, not guile.
guile_bin=${GUILE:-$(command -v guile3 || command -v guile-3.0 || command -v guile || echo guile)}
guile_v=$("$guile_bin" --version 2>/dev/null | head -1)
gforth_v=$(${GFORTH:-gforth} --version 2>&1 | head -1)

case "$job" in
  test|freebsd)
    metrics=$(printf '{"unit_pass":%s,"unit_fail":%s,"diff_lines":%s,"diff_pass":%s}' \
      "$(cnt '^PASS (cell|vm|outer)-test')" "$(cnt '^FAIL (cell|vm|outer)-test')" \
      "$(js "$(num 's/^PASS frames-diff (\([0-9]*\) lines.*/\1/p')")" \
      "$(if grep -q '^PASS frames-diff' "$log"; then echo true; else echo false; fi)") ;;
  trials)
    metrics=$(printf '{"layer0_pass":%s,"layer0_total":%s,"pass":%s,"fail":%s,"skip":%s}' \
      "$(js "$(num 's/^layer 0: \([0-9]*\)\/[0-9]*/\1/p')")" \
      "$(js "$(num 's/^layer 0: [0-9]*\/\([0-9]*\)/\1/p')")" \
      "$(js "$(num 's/^pass \([0-9]*\) .*/\1/p')")" \
      "$(js "$(num 's/^pass [0-9]*  fail \([0-9]*\).*/\1/p')")" \
      "$(js "$(num 's/.*skip \([0-9]*\)$/\1/p')")") ;;
  mutants)
    metrics=$(printf '{"killed":%s,"survived":%s,"not_applied":%s,"by_oracle":{"compile":%s,"unit":%s,"diff":%s}}' \
      "$(js "$(num 's/^mutants killed \([0-9]*\).*/\1/p')")" \
      "$(js "$(num 's/.*survived \([0-9]*\).*/\1/p')")" \
      "$(js "$(num 's/.*not applied \([0-9]*\).*/\1/p')")" \
      "$(cnt '^killed \(compile')" "$(cnt '^killed \(unit')" "$(cnt '^killed \(diff')") ;;
  *) metrics='{}' ;;
esac

mkdir -p "$(dirname "$out")"
printf '{"job":%s,"status":%s,"sha":%s,"ref":%s,"run_id":%s,"run_attempt":%s,"event":%s,"date":%s,"os":%s,"guile":%s,"gforth":%s,"metrics":%s}\n' \
  "$(str "$job")" "$(str "${JOB_STATUS:-unknown}")" "$(str "${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null)}")" \
  "$(str "${GITHUB_REF_NAME:-}")" "$(js "${GITHUB_RUN_ID:-}")" "$(js "${GITHUB_RUN_ATTEMPT:-}")" \
  "$(str "${GITHUB_EVENT_NAME:-local}")" "$(str "$(date -u +%Y-%m-%dT%H:%M:%SZ)")" \
  "$(str "$(uname -sm)")" "$(str "$guile_v")" "$(str "$gforth_v")" "$metrics" > "$out"
cat "$out"

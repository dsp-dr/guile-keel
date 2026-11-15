#!/usr/bin/env bash
# Mutation testing: break the implementation on purpose, one edit at a time,
# and check that the suites notice. A mutant that nothing catches is a gap in
# the tests, not a bug in the source.
#
# Two oracles are tried in order, cheapest first:
#   unit   the three SRFI-64 suites (gmake unit)
#   diff   the differential test against gforth (gmake frames-diff)
#
# Usage: tests/mutants.sh [-q]        from the repository root or anywhere
# Exit 0 if every mutant was killed, 1 if any survived or could not be applied.
set -u
cd "$(dirname "$0")/.." || exit 1

GMAKE=${GMAKE:-gmake}
command -v "$GMAKE" > /dev/null 2>&1 || GMAKE="make"
# Cap each mutant: one of them disables the interpreter's step budget, so a
# runaway is a possible outcome rather than a surprise.
PER_MUTANT_TIMEOUT=${PER_MUTANT_TIMEOUT:-180}
if command -v timeout > /dev/null 2>&1; then
  TO=(timeout "$PER_MUTANT_TIMEOUT")
else
  TO=()
fi

SOURCES=(src/keel/cell.scm src/keel/vm.scm src/keel/outer.scm)

# Every mutation is undone with git, not with a saved copy: if this script is
# killed outright no trap runs, and a stashed copy in /tmp would be the only
# record of the original. That cost a restore-from-HEAD once already. The price
# is that the sources must be committed before starting.
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "mutants: not a git repository; refusing to run without a way to undo" >&2
  exit 1
fi
if ! dirty=$(git diff --name-only -- "${SOURCES[@]}") || [ -n "$dirty" ]; then
  echo "mutants: these sources have uncommitted changes, and this script would" >&2
  echo "         revert them with git checkout. Commit or stash first:" >&2
  printf '           %s\n' "$dirty" >&2
  exit 1
fi

tmpf=$(mktemp) || exit 1
current=
restore() { [ -n "$current" ] && git checkout -- "$current"; current=; }
cleanup() { restore; rm -f "$tmpf"; }
trap cleanup EXIT INT TERM HUP

killed=0 survived=0 broken=0

# file | what the mutation does | sed expression
mutate() {
  file=$1 desc=$2 expr=$3

  current=$file
  sed "$expr" "$file" > "$tmpf" && cat "$tmpf" > "$file"

  if git diff --quiet -- "$file"; then
    printf 'NOT APPLIED  %-44s (%s)\n' "$desc" "$file"
    broken=$((broken + 1)); restore; return
  fi

  oracle=
  "$GMAKE" clean > /dev/null 2>&1 || true
  if ! "${TO[@]}" "$GMAKE" build > /dev/null 2>&1; then
    oracle="compile"
  elif ! "${TO[@]}" "$GMAKE" unit > /dev/null 2>&1; then
    oracle="unit"
  elif ! "${TO[@]}" "$GMAKE" frames-diff > /dev/null 2>&1; then
    oracle="diff"
  fi

  if [ -n "$oracle" ]; then
    printf 'killed (%-7s) %-44s\n' "$oracle" "$desc"
    killed=$((killed + 1))
  else
    printf 'SURVIVED      %-44s (%s)\n' "$desc" "$file"
    survived=$((survived + 1))
  fi
  restore
}

C=src/keel/cell.scm
V=src/keel/vm.scm
O=src/keel/outer.scm

# ---- cell arithmetic: the layer every other layer assumes ----
mutate "$C" 'cell+ adds -> subtracts'          's|(u32 (+ a b))|(u32 (- a b))|'
mutate "$C" 'cell+ drops the 32-bit wrap'      's|(define (cell+ a b) (u32 (+ a b)))|(define (cell+ a b) (+ a b))|'
mutate "$C" 'nand loses its negation'          's|(u32 (lognot (logand a b)))|(u32 (logand a b))|'
mutate "$C" 'nand becomes nor'                 's|(u32 (lognot (logand a b)))|(u32 (lognot (logior a b)))|'
mutate "$C" '0= inverts its sense'             's|(if (zero? (u32 a)) true-flag 0)|(if (zero? (u32 a)) 0 true-flag)|'
mutate "$C" '0= returns 1 rather than all bits' 's|(if (zero? (u32 a)) true-flag 0)|(if (zero? (u32 a)) 1 0)|'
mutate "$C" 'um* high cell shifted by 16'      's|(u32 (ash p -32))|(u32 (ash p -16))|'
mutate "$C" 'um* swaps lo and hi'              's|(values (u32 p) (u32 (ash p -32)))|(values (u32 (ash p -32)) (u32 p))|'
mutate "$C" 'um/mod loses overflow check'      's|(when (> q cell-mask)|(when (> q (* 2 cell-mask))|'
mutate "$C" 'um/mod loses div-by-zero check'   's|(when (zero? dd)|(when (and #f (zero? dd))|'
mutate "$C" 'um/mod swaps rem and quot'        's|(values (remainder ud dd) q)|(values q (remainder ud dd))|'
mutate "$C" 's32 sign boundary off by a bit'   's|(if (>= u #x80000000)|(if (>= u #x40000000)|'

# ---- vm: memory, stacks, inner interpreter ----
mutate "$V" 'memory becomes big-endian'        's|(endianness little)|(endianness big)|g'
mutate "$V" 'data stack grows up'              's|(let ((sp (- (vm-sp vm) 4)))|(let ((sp (+ (vm-sp vm) 4)))|'
mutate "$V" 'stack underflow check off by one' 's|(when (>= sp s0) (err "data stack underflow"))|(when (> sp s0) (err "data stack underflow"))|'
mutate "$V" 'return stack underflow unchecked' 's|(when (>= rp r0) (err "return stack underflow"))|(when (and #f (>= rp r0)) (err "return stack underflow"))|'
mutate "$V" '@ bounds check ignores cell width' 's|(unless (and (>= a 0) (<= (+ a 4) mem-size)) (err "@: address ~a out of range" a))|(unless (and (>= a 0) (<= a mem-size)) (err "@: address ~a out of range" a))|'
mutate "$V" 'DOVAR pushes the wrong body offset' 's|((1) (push! vm (+ w 8))|((1) (push! vm (+ w 4))|'
mutate "$V" 'DOCON reads the wrong cell'       's|((2) (push! vm (mem@ vm (+ w 4)))|((2) (push! vm (mem@ vm (+ w 8)))|'
mutate "$V" 'exit does not pop the return stack' 's|((23) (set-vm-ip! vm (rpop! vm))|((23) (set-vm-ip! vm (vm-ip vm))|'
mutate "$V" 'key returns 0 at end of input'    's|(if (eof-object? c) cell-mask (char->integer c))|(if (eof-object? c) 0 (char->integer c))|'
mutate "$V" 'emit drops the high-bit mask'     's|(integer->char (logand (pop! vm) 255))|(integer->char (logand (pop! vm) 127))|'
mutate "$V" 'um/mod operands popped in reverse' 's|(let\* ((d (pop! vm)) (hi (pop! vm)) (lo (pop! vm)))|(let* ((d (pop! vm)) (lo (pop! vm)) (hi (pop! vm)))|'
mutate "$V" 'step budget never runs out'       's|(when (<= n 0) (set-vm-steps! vm 0) (err "step limit reached"))|(when (and #f (<= n 0)) (err "step limit reached"))|'

# ---- outer: headers, parsing, host words ----
mutate "$O" 'immediate and hidden flags swap'  's|(define flag-immediate 128)|(define flag-immediate 64)|'
mutate "$O" 'header alignment off by one'      's|(define (align a) (logand (+ a 3) (lognot 3)))|(define (align a) (logand (+ a 2) (lognot 3)))|'
mutate "$O" 'name length mask too narrow'      's|(logand (memc@ vm (+ h 4)) 31)|(logand (memc@ vm (+ h 4)) 15)|g'
mutate "$O" 'find ignores the hidden flag'     's|((and (zero? (logand (memc@ vm (+ h 4)) flag-hidden))|((and #t|'
mutate "$O" 'negative numbers parse as positive'   's|(u32 (if neg (- acc) acc))|(u32 acc)|'
mutate "$O" 'comma! does not advance here'     's|(set-here! vm (+ h 4))|(set-here! vm h)|'

printf '\nmutants killed %d   survived %d   not applied %d\n' "$killed" "$survived" "$broken"
[ "$survived" -eq 0 ] && [ "$broken" -eq 0 ]

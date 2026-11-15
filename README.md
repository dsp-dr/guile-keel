# guile-keel

A Guile 3 host for [forth-keel](https://github.com/aygp-dr/forth-keel): the
13 keel primitives and an inner interpreter in Scheme, and the frames layer
(Forth layer 0) in Forth, built from those primitives only.

| Layer | File | Size |
|-------|------|------|
| cell arithmetic (32-bit) | `src/keel/cell.scm` | 36 lines |
| memory, stacks, inner interpreter | `src/keel/vm.scm` | 165 lines |
| dictionary, bootstrap words, outer interpreter | `src/keel/outer.scm` | 202 lines |
| frames: 151 Forth definitions | `forth/frames.fs` | 193 lines |

Results on this host (Guile 3.0.9, x86_64):

- forth-keel sea-trials layer 0: **22/22**, about 6 s for the whole suite.
- `tests/frames-check.fs`: output identical to gforth 0.7.3 (57 lines of
  arithmetic, comparison, division, output, loop and defining-word cases).
- Layer x (strings `compare`, `catch`/`throw`, floats, `allocate`, locals): 0/7,
  as expected; these wordsets are outside the layered build.

## Build order

Each step was tested before the next one started.

```mermaid
flowchart LR
  C["1 cell arithmetic<br/>+ nand 0= um* um/mod<br/>on 32-bit values"] --> M["2 memory<br/>64 KiB bytevector,<br/>@ ! little-endian"]
  M --> V["3 inner interpreter<br/>stacks in memory,<br/>indirect threading, NEXT"]
  V --> O["4 outer interpreter<br/>parse, find, number,<br/>: ; create does> '"]
  O --> F["5 frames.fs<br/>Forth from primitives"]
  F --> T["6 sea-trials<br/>layer 0"]
```

The 32-bit arithmetic comes first because every later layer assumes it:
`+` must wrap at 2^32, `um*` must return a 64-bit product as two cells, and
`um/mod` must reject a quotient that does not fit. `tests/cell-test.scm`
checks each primitive against exact integer arithmetic on edge values and
random values before any memory or interpreter code exists.

## The keel

Primitives (exactly the forth-keel R-K-01 list):

| Word | Stack | Code |
|------|-------|------|
| `@` | `( addr -- x )` | 16 |
| `!` | `( x addr -- )` | 17 |
| `sp@` | `( -- addr )` address of the top data-stack item | 18 |
| `rp@` | `( -- addr )` address of the top return-stack item | 19 |
| `0=` | `( x -- f )` | 20 |
| `+` | `( a b -- a+b )` mod 2^32 | 21 |
| `nand` | `( a b -- ~(a&b) )` | 22 |
| `exit` | `( -- ) ( R: a -- )` | 23 |
| `key` | `( -- c )` -1 at end of input | 24 |
| `emit` | `( c -- )` | 25 |
| `execute` | `( xt -- )` | 26 |
| `um*` | `( u1 u2 -- lo hi )` | 27 |
| `um/mod` | `( lo hi u -- rem quot )` | 28 |

Bootstrap words supplied by the host, because they parse input or lay down
headers (sectorforth makes the same split): `:` `;` `create` `does>` `'`, the
comment syntax `\` and `(`, and the constants `state >in #tib dp latest base
tib s0`. Code numbers 0-4 are the inner interpreter's own: ENTER, DOVAR,
DOCON, HALT, DODOES.

```mermaid
flowchart TD
  F["fetch: w = mem[ip], ip += 4"] --> D{"code = mem[w]"}
  D -->|"0 ENTER"| E["rpush ip, ip = w+4"]
  D -->|"1 DOVAR"| VAR["push w+8"]
  D -->|"2 DOCON"| CON["push mem[w+4]"]
  D -->|"4 DODOES"| DOES["push w+8, rpush ip, ip = mem[w+4]"]
  D -->|"16-28 primitive"| P["run primitive"]
  D -->|"32-36 host word"| H["run host word"]
  D -->|"3 HALT"| X["return to the outer interpreter"]
  E --> F
  VAR --> F
  CON --> F
  DOES --> F
  P --> F
  H --> F
```

Memory map (byte addresses, 64 KiB):

| Range | Use |
|-------|-----|
| `0x0000-0x003F` | system variables: state, >in, #tib, dp, latest, base, scratch thread |
| `0x0040-0x023F` | terminal input buffer (512 bytes) |
| `0x0400-0x7FFF` | dictionary (frames use about 7.5 KiB) |
| `0x8000-0xDFFF` | heap, reserved for planking's two semispaces |
| `0xE000-0xEFFF` | data stack, grows down from `0xF000` |
| `0xF000-0xFFFF` | return stack, grows down from `0x10000` |

Header: link cell, flags/length byte (bit 7 immediate, bit 6 hidden), name,
padding to a cell, then the code field (the xt).

## How frames.fs bootstraps

1. **No literals yet.** `dup` is `sp@ @`; `(-1)` and `(1)` are built from
   `nand` and `+`; `(cell)` is `sp@ sp@ -`. These words are slow because each
   use re-derives its constants.
2. **Constants.** `(constant)` uses `create` and then writes the DOCON code
   into the new word's code field, so `-1 0 1 cell 3cells` each cost one
   step.
3. **Fast core.** `lit`, `-`, `over`, `swap` and the rest are redefined on top
   of the constants. `lit` reads the cell after its call site through `rp@`
   and moves the return address past it.
4. **Return stack.** `>r` and `r>` rewrite return addresses with `rp@` and
   `!`, as in sectorforth. `drop` is `sp@ !` (store the top item into its own
   slot), because sectorforth's `dup - +` needs a second item below and this
   keel checks for underflow.
5. **Everything else** (control flow, division, output, parsing, `do` loops
   with `leave`, `case`, `defer`, `value`/`to`) is ordinary Forth on top.

Step 2 exists because of a measurement: with only the slow words,
`220-sicp-1.2.2-fib` needed more than 200 million steps and 15 s; after the
constants it takes 1.5 s.

## Usage

```sh
make            # build, unit tests (cell, vm, outer), differential test vs gforth
make trials     # forth-keel sea-trials layer 0 (FORTH_KEEL=../../aygp-dr/forth-keel)
bin/keel file.fs            # load frames.fs, then file.fs
bin/keel -e '10 0 do i . loop'   # error: do outside a definition, as in gforth
bin/keel --bare -e '3 4 + 48 + emit'   # primitives only, no frames.fs
```

`KEEL_STEPS` sets the instruction budget per top-level word (default 200
million); exceeding it is an error rather than a hang.

## Known differences from gforth

- Reading below an empty stack with `dup` or `over` is not detected:
  both are memory reads (`sp@ @`), not pops. gforth reports a stack underflow.
- `do`, `if` and the other control words are immediate everywhere, without
  gforth's interpret-state warnings.
- Error messages are `keel: FILE:LINE: message` and stop the file.
- Cells are 32 bits; gforth on x86_64 has 64-bit cells.

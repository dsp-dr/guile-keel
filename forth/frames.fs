\ frames.fs -- Forth layer 0 for forth-keel, written from the 13 keel
\ primitives  @ ! sp@ rp@ 0= + nand exit key emit execute um* um/mod
\ and the keel bootstrap words  : ; create does> '  and constants
\ state >in #tib dp latest base tib s0.
\ Until lit is defined (section 1b), no definition may contain a number literal.

\ ---- 1. bootstrap: slow words, no literals ------------------------------------
\ The parenthesized words are built from primitives alone and are slow
\ (every use re-derives -1, 1 and the cell size). They exist only to build
\ section 1b and are not used after it.
: dup ( x -- x x ) sp@ @ ;
: (-1) ( -- -1 ) dup dup nand dup dup nand nand ;
: (1) ( -- 1 ) (-1) dup + dup nand ;
: invert ( x -- ~x ) dup nand ;
: (-) ( a b -- a-b ) invert (1) + + ;
: (cell) ( -- n ) sp@ sp@ (-) ;
: (over) ( a b -- a b a ) sp@ (cell) + @ ;
: (swap) ( a b -- b a ) (over) (over) sp@ (cell) + (cell) + (cell) + ! sp@ (cell) + ! ;
\ (constant) builds a word whose code field is the keel's DOCON (code 2):
\ create leaves dp at xt+8; the value goes in xt+4.
: (constant) ( x "name" -- ) create dp @ (cell) (-) (swap) (over) ! (cell) (-) (1) (1) + (swap) ! ;

\ ---- 1b. constants and fast core words -------------------------------------------
(-1) (constant) -1
(-1) dup nand (constant) 0
(1) (constant) 1
(cell) (constant) cell
(cell) (cell) + (cell) + (constant) 3cells
: lit ( -- x ) rp@ @ dup cell + rp@ ! @ ;
: negate ( n -- -n ) invert 1 + ;
: - ( a b -- a-b ) negate + ;
: and ( x y -- x&y ) nand invert ;
: cell+ ( a -- a' ) cell + ;
: drop ( x -- ) sp@ ! ;
: over ( a b -- a b a ) sp@ cell + @ ;
: swap ( a b -- b a ) over over sp@ 3cells + ! sp@ cell + ! ;

\ ---- 2. literals and compiling ---------------------------------------------
: , ( x -- ) dp @ ! dp @ cell+ dp ! ;
: here ( -- addr ) dp @ ;
: or ( x y -- x|y ) invert swap invert and invert ;
: immediate ( -- ) latest @ cell+ dup @ 128 or swap ! ;
: [ ( -- ) 0 state ! ; immediate
: ] ( -- ) -1 state ! ;

\ ---- 3. return stack --------------------------------------------------------
: >rexit ( addr -- ) rp@ ! ;
: >r ( x -- ) ( R: -- x ) rp@ @ swap rp@ ! >rexit ;
: r> ( -- x ) ( R: x -- ) rp@ cell+ @ rp@ @ rp@ cell+ ! lit [ here 3cells + , ] rp@ ! ;
: r@ ( -- x ) ( R: x -- x ) rp@ cell+ @ ;
: nip ( a b -- b ) swap drop ;
: tuck ( a b -- b a b ) swap over ;
: 2dup ( a b -- a b a b ) over over ;
: 2drop ( a b -- ) drop drop ;
: rot ( a b c -- b c a ) >r swap r> swap ;
: -rot ( a b c -- c a b ) rot rot ;
: xor ( x y -- x^y ) over over nand dup >r nand swap r> nand nand ;
: = ( a b -- f ) - 0= ;
: <> ( a b -- f ) = invert ;
: 0<> ( x -- f ) 0= 0= ;

\ ---- 4. control flow ---------------------------------------------------------
: ['] ( -- xt ) rp@ @ dup cell + rp@ ! @ ;
: branch ( -- ) rp@ @ dup @ + rp@ ! ;
: ?branch ( f -- ) 0= rp@ @ @ cell - and rp@ @ + cell+ rp@ ! ;
: >mark ( -- orig ) here 0 , ;
: >resolve ( orig -- ) here over - swap ! ;
: <resolve ( dest -- ) here - , ;
: if ( -- orig ) ['] ?branch , >mark ; immediate
: then ( orig -- ) >resolve ; immediate
: else ( orig1 -- orig2 ) ['] branch , >mark swap >resolve ; immediate
: begin ( -- dest ) here ; immediate
: until ( dest -- ) ['] ?branch , <resolve ; immediate
: again ( dest -- ) ['] branch , <resolve ; immediate
: while ( dest -- orig dest ) ['] ?branch , >mark swap ; immediate
: repeat ( orig dest -- ) ['] branch , <resolve >resolve ; immediate
: aligned ( a -- a' ) 3 + -4 and ;
: c@ ( addr -- c ) @ 255 and ;
: >xt ( header -- xt ) cell+ dup c@ 31 and + 1 + aligned ;
: recurse ( -- ) latest @ >xt , ; immediate

\ ---- 5. comparison and arithmetic -------------------------------------------
: true ( -- f ) -1 ;
: false ( -- f ) 0 ;
: 0< ( n -- f ) -2147483648 and 0<> ;
: < ( a b -- f ) 2dup xor 0< if drop 0< exit then - 0< ;
: > ( a b -- f ) swap < ;
: 0> ( n -- f ) 0 > ;
: u< ( a b -- f ) 2dup xor 0< if nip 0< exit then - 0< ;
: u> ( a b -- f ) swap u< ;
: 1+ ( n -- n+1 ) 1 + ;
: 1- ( n -- n-1 ) 1 - ;
: 2* ( n -- 2n ) dup + ;
: cells ( n -- n*cell ) 2* 2* ;
: ?dup ( x -- x x | 0 ) dup if dup then ;
: abs ( n -- |n| ) dup 0< if negate then ;
: min ( a b -- min ) 2dup > if swap then drop ;
: max ( a b -- max ) 2dup < if swap then drop ;
: within ( n lo hi -- f ) over - >r - r> u< ;
: * ( a b -- a*b ) um* drop ;
: u2/ ( u -- u/2 ) 0 2 um/mod nip ;
: 2/ ( n -- n/2 ) dup u2/ swap 0< if -2147483648 or then ;
: lshift ( x n -- x' ) begin dup while swap 2* swap 1- repeat drop ;
: rshift ( x n -- x' ) begin dup while swap u2/ swap 1- repeat drop ;
: s>d ( n -- d ) dup 0< ;
: dnegate ( d -- -d ) invert swap invert 1+ dup 0= rot swap - ;
: dabs ( d -- |d| ) dup 0< if dnegate then ;
: m* ( a b -- d ) 2dup xor >r abs swap abs um* r> 0< if dnegate then ;
: sm/rem ( d n -- rem quot ) 2dup xor >r over >r abs >r dabs r> um/mod r> 0< if swap negate swap then r> 0< if negate then ;
: fm/mod ( d n -- rem quot )
  dup >r sm/rem over dup 0<> swap 0< r@ 0< xor and if 1- swap r> + swap else r> drop then ;
: /mod ( a b -- rem quot ) >r s>d r> fm/mod ;
: / ( a b -- quot ) /mod nip ;
: mod ( a b -- rem ) /mod drop ;
: */mod ( a b c -- rem quot ) >r m* r> fm/mod ;
: */ ( a b c -- quot ) */mod nip ;

\ ---- 6. memory and defining words ---------------------------------------------
: c! ( c addr -- ) dup @ -256 and rot 255 and or swap ! ;
: +! ( n addr -- ) dup @ rot + swap ! ;
: allot ( n -- ) dp +! ;
: c, ( c -- ) here c! 1 allot ;
: align ( -- ) here aligned dp ! ;
: >body ( xt -- addr ) cell+ cell+ ;
: variable ( "name" -- ) create 0 , ;
: constant ( x "name" -- ) create , does> @ ;
: value ( x "name" -- ) create , does> @ ;
: to ( x "name" -- ) ' >body state @ if ['] lit , , ['] ! , else ! then ; immediate
: defer ( "name" -- ) create 0 , does> @ execute ;
: is ( xt "name" -- ) ' >body ! ;
: :noname ( -- xt ) here 0 , ] ;
: fill ( addr n c -- ) swap begin dup 0> while >r 2dup swap c! swap 1+ swap r> 1- repeat 2drop drop ;
: move ( src dst n -- ) begin dup 0> while >r over c@ over c! 1+ swap 1+ swap r> 1- repeat drop 2drop ;

\ ---- 7. more stack words -------------------------------------------------------
: 2>r ( a b -- ) ( R: -- a b ) r> -rot swap >r >r >r ;
: 2r> ( -- a b ) ( R: a b -- ) r> r> r> swap rot >r ;
: 2swap ( a b c d -- c d a b ) rot >r rot r> ;
: 2over ( a b c d -- a b c d a b ) >r >r 2dup r> r> 2swap ;
: pick ( xu .. x0 u -- xu .. x0 xu ) 1+ cells sp@ + @ ;
: roll ( xu .. x0 u -- xu-1 .. x0 xu ) ?dup if swap >r 1- recurse r> swap then ;
: depth ( -- n ) s0 sp@ - 2/ 2/ 1- ;

\ ---- 8. output -------------------------------------------------------------------
: hex ( -- ) 16 base ! ;
: decimal ( -- ) 10 base ! ;
: bl ( -- c ) 32 ;
: cr ( -- ) 10 emit ;
: space ( -- ) bl emit ;
: spaces ( n -- ) begin dup 0> while space 1- repeat drop ;
: type ( addr n -- ) begin dup 0> while over c@ emit 1- swap 1+ swap repeat 2drop ;
: digit ( n -- c ) dup 9 > if 7 + then 48 + ;
: (u.) ( u -- ) 0 base @ um/mod ?dup if recurse then digit emit ;
: u. ( u -- ) (u.) space ;
: . ( n -- ) dup 0< if 45 emit negate then u. ;
: udigits ( u -- n ) 1 swap begin 0 base @ um/mod nip dup while swap 1+ swap repeat drop ;
: .r ( n w -- ) over dup 0< if negate udigits 1+ else udigits then - spaces dup 0< if 45 emit negate then (u.) ;

\ ---- 9. parsing and strings ----------------------------------------------------------
: parse ( c "text<c>" -- addr n )
  >r tib >in @ + 0
  begin >in @ #tib @ < if 2dup + c@ r@ <> else 0 then while 1+ >in @ 1+ >in ! repeat
  >in @ #tib @ < if >in @ 1+ >in ! then r> drop ;
: skip-bl ( -- ) begin >in @ #tib @ < if tib >in @ + c@ 33 < else 0 then while >in @ 1+ >in ! repeat ;
: parse-name ( "name" -- addr n ) skip-bl bl parse ;
: char ( "c" -- c ) parse-name drop c@ ;
: [char] ( "c" -- ) char ['] lit , , ; immediate
: s, ( addr n -- ) dup , begin dup 0> while over c@ c, 1- swap 1+ swap repeat 2drop align ;
: (.") ( -- ) r> dup @ swap cell+ 2dup + aligned >r swap type ;
: (s") ( -- addr n ) r> dup @ swap cell+ 2dup + aligned >r swap ;
: ." ( "text<quote>" -- ) 34 parse state @ if ['] (.") , s, else type then ; immediate
: s" ( "text<quote>" -- addr n ) 34 parse state @ if ['] (s") , s, then ; immediate

\ ---- 10. counted loops and case -------------------------------------------------------
variable leaves
: (do) ( limit start -- ) ( R: -- limit index ) r> -rot swap >r >r >r ;
: (?do) ( limit start -- ) 2dup = if 2drop r> dup @ + >r exit then r> -rot swap >r >r cell+ >r ;
: (loop) ( -- ) r> r> 1+ r@ over = if r> 2drop cell+ >r exit then >r dup @ + >r ;
: (+loop) ( n -- ) r> swap r> r@ - 2dup + over xor 0< if 2drop r> drop cell+ >r exit then + r@ + >r dup @ + >r ;
: (leave) ( -- ) r> r> r> 2drop dup @ + >r ;
: i ( -- n ) r> r@ swap >r ;
: j ( -- n ) r> r> r> r@ -rot >r >r swap >r ;
: unloop ( -- ) r> r> r> 2drop >r ;
: resolve-leaves ( -- ) leaves @ begin ?dup while dup @ swap >resolve repeat ;
: do ( -- old dest ) ['] (do) , leaves @ 0 leaves ! here ; immediate
: ?do ( -- old dest ) ['] (?do) , leaves @ here 0 , leaves ! here ; immediate
: leave ( -- ) ['] (leave) , here leaves @ , leaves ! ; immediate
: loop ( old dest -- ) ['] (loop) , <resolve resolve-leaves leaves ! ; immediate
: +loop ( old dest -- ) ['] (+loop) , <resolve resolve-leaves leaves ! ; immediate
: case ( -- 0 ) 0 ; immediate
: of ( -- orig ) ['] over , ['] = , ['] ?branch , >mark ['] drop , ; immediate
: endof ( orig1 -- orig2 ) ['] branch , >mark swap >resolve ; immediate
: endcase ( 0 orig.. -- ) ['] drop , begin ?dup while >resolve repeat ; immediate

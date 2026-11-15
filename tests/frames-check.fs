\ Differential check: gforth and keel must print the same text.
\ Values stay in 32-bit range and avoid operations whose result differs
\ between 32- and 64-bit cells (overflow, negate of min-n, rshift of negatives).
create vals -1000 , -7 , -3 , -1 , 0 , 1 , 2 , 3 , 7 , 1000 ,
10 constant #v
: v ( i -- n ) cells vals + @ ;
: binop ( xt -- ) #v 0 do #v 0 do j v i v 2 pick execute . loop loop drop cr ;
: bin/ ( xt -- ) #v 0 do #v 0 do i v if j v i v 2 pick execute . then loop loop drop cr ;
: binp ( xt -- ) #v 0 do #v 0 do i v if j v i v 2 pick execute then loop loop drop cr ;  \ xt prints
: un ( xt -- ) #v 0 do i v over execute . loop drop cr ;
' + binop ' - binop ' * binop ' min binop ' max binop
' = binop ' <> binop ' < binop ' > binop ' u< binop ' u> binop
' and binop ' or binop ' xor binop
' / bin/ ' mod bin/
: qr ( a b -- ) /mod . . ;
' qr binp
: fm ( a b -- ) >r s>d r> fm/mod . . ;
: sm ( a b -- ) >r s>d r> sm/rem . . ;
' fm binp ' sm binp
: star-slash ( a b -- n ) 13 */ ;
' star-slash binop
: mstar ( a b -- n ) m* drop ;  \ low cell only: the high cell differs between 32- and 64-bit
' mstar binop
' negate un ' abs un ' 0= un ' 0< un ' 0> un ' 0<> un ' 1+ un ' 1- un ' 2* un ' 2/ un ' invert un
: within? ( n -- f ) -3 3 within ;
' within? un
1 0 lshift . 1 5 lshift . 3 4 lshift . 256 4 rshift . 1000 3 rshift . cr
-2147483648 0< . 2147483647 0< . -2147483648 2147483647 < . cr
\ number output
-42 . 0 . 7 . -42 6 .r 42 6 .r 0 3 .r cr
hex 255 . -255 . 4096 . decimal cr
5 2 base ! . decimal 10 . cr
\ stack words
1 2 3 rot . . . 1 2 3 -rot . . . 1 2 3 4 2swap . . . . 1 2 3 4 2over . . . . . . cr
10 20 30 40 3 roll . . . . 10 20 30 2 pick . . . . depth . cr
\ control flow
: nest ( -- ) 4 1 do 3 0 do i j * . loop loop ;
nest cr
: early ( -- ) 100 0 do i dup . 3 = if leave then 7 +loop ;
: early2 ( -- ) 10 0 do i 4 = if leave then i . loop ." after" ;
early cr early2 cr
: down ( -- ) -5 5 do i . -3 +loop ;
down cr
: skip7 ( -- ) 7 7 ?do i . loop ." skipped" ;
skip7 cr
: unl ( -- n ) 10 0 do i 6 = if i unloop exit then loop -1 ;
unl . cr
: sel ( n -- ) case 1 of ." one " endof 2 of ." two " endof ." other " endcase ;
0 sel 1 sel 2 sel 3 sel cr
: cnt ( n -- ) begin dup 0> while dup . 1- repeat drop ;
5 cnt cr
: cnt2 ( n -- ) begin dup . 1- dup 0= until drop ;
3 cnt2 cr
\ defining words
defer op
' + is op 3 4 op .
' * is op 3 4 op . cr
5 value vv vv . 9 to vv vv .
: set-vv ( n -- ) to vv ; 11 set-vv vv . cr
:noname ( n -- n ) dup * ; constant sq 9 sq execute . cr
: arr ( n "name" -- ) create cells allot does> swap cells + ;
4 arr aa 77 2 aa ! 2 aa @ . cr
: r-test ( -- ) 1 2 2>r 3 2r> . . . ;
r-test cr
: fact ( n -- n! ) dup 2 < if drop 1 exit then dup 1- recurse * ;
10 fact . 12 fact . cr
char A . : zc [char] z ; zc . ." quote" cr
: ts ( -- ) s" text" type ; ts cr

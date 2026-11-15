;;; (keel cell) -- 32-bit cell arithmetic for the keel primitives.
;;; Every cell is held as an exact integer in [0, 2^32). Signed views are
;;; computed only where a primitive needs them.
(define-module (keel cell)
  #:export (cell-bytes cell-mask u32 s32 true-flag
            cell+ cell-nand cell-0= cell-um* cell-um/mod))

(define cell-bytes 4)
(define cell-mask #xFFFFFFFF)
(define true-flag cell-mask)            ; Forth true: all bits set

(define (u32 n) (logand n cell-mask))
(define (s32 n)
  (let ((u (u32 n)))
    (if (>= u #x80000000) (- u #x100000000) u)))

;; +    ( n1 n2 -- n3 )      sum modulo 2^32
(define (cell+ a b) (u32 (+ a b)))
;; nand ( x1 x2 -- x3 )      bitwise not-and
(define (cell-nand a b) (u32 (lognot (logand a b))))
;; 0=   ( x -- flag )        true if x is zero
(define (cell-0= a) (if (zero? (u32 a)) true-flag 0))
;; um*  ( u1 u2 -- ud )      unsigned 32x32 -> 64 product, returned as (values lo hi)
(define (cell-um* a b)
  (let ((p (* (u32 a) (u32 b))))
    (values (u32 p) (u32 (ash p -32)))))
;; um/mod ( ud u -- urem uquot )  ud is (lo, hi); returned as (values rem quot)
(define (cell-um/mod lo hi d)
  (let ((ud (+ (u32 lo) (ash (u32 hi) 32)))
        (dd (u32 d)))
    (when (zero? dd)
      (throw 'keel-error "um/mod: division by zero"))
    (let ((q (quotient ud dd)))
      (when (> q cell-mask)
        (throw 'keel-error "um/mod: quotient does not fit in a cell"))
      (values (remainder ud dd) q))))

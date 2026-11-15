;;; Unit and property tests for (keel cell): each primitive against exact integer arithmetic.
(use-modules (keel cell) (srfi srfi-1) (srfi srfi-64) (ice-9 receive))
(test-runner-current (test-runner-simple))
(define rng (seed->random-state 20261115))
(define edges (list 0 1 2 3 #x3FFFFFFF #x40000000 #x7FFFFFFF #x80000000 #x80000001
                    #xFFFFFFFE #xFFFFFFFF #x10000 #xFFFF))

;; The key an expression raises, or 'no-error. SRFI-64's test-error does not
;; enforce the error kind in the simple runner, so "it threw something" would
;; pass even when the something is a host arithmetic error escaping from a
;; missing guard. Mutation testing found exactly that gap.
(define (raised-key thunk)
  (catch #t (lambda () (thunk) 'no-error) (lambda (key . args) key)))
(define (rand-u32) (random #x100000000 rng))
(define (samples n) (append edges (map (lambda (_) (rand-u32)) (iota n))))
(define (all-pairs xs) (append-map (lambda (a) (map (lambda (b) (cons a b)) xs)) xs))

(test-begin "cell")

(test-group "examples"
  (test-equal "+ wraps" 0 (cell+ #xFFFFFFFF 1))
  (test-equal "+ max+max" #xFFFFFFFE (cell+ #xFFFFFFFF #xFFFFFFFF))
  (test-equal "nand 0 0" #xFFFFFFFF (cell-nand 0 0))
  (test-equal "nand -1 -1" 0 (cell-nand #xFFFFFFFF #xFFFFFFFF))
  (test-equal "0= 0" true-flag (cell-0= 0))
  (test-equal "0= 1" 0 (cell-0= 1))
  (test-equal "s32 of max" -1 (s32 #xFFFFFFFF))
  (test-equal "s32 of min" -2147483648 (s32 #x80000000))
  (test-equal "u32 of -1" #xFFFFFFFF (u32 -1))
  (receive (lo hi) (cell-um* #xFFFFFFFF #xFFFFFFFF)
    (test-equal "um* lo" 1 lo)
    (test-equal "um* hi" #xFFFFFFFE hi))
  (receive (r q) (cell-um/mod 10 0 3)
    (test-equal "um/mod q" 3 q)
    (test-equal "um/mod r" 1 r))
  (receive (r q) (cell-um/mod 0 1 2)   ; 2^32 / 2
    (test-equal "um/mod 2^32/2" #x80000000 q))
  ;; s32 must only treat the top bit as the sign. A boundary set anywhere
  ;; lower still answers correctly for #x80000000 and #xFFFFFFFF, so the
  ;; positive side needs probing too.
  (test-equal "s32 at 2^30 stays positive" #x40000000 (s32 #x40000000))
  (test-equal "s32 just below the sign bit stays positive" #x7FFFFFFF (s32 #x7FFFFFFF))
  (test-equal "s32 at the sign bit is the most negative cell" -2147483648 (s32 #x80000000))
  ;; These must be keel's own error, not a host divide-by-zero or bignum
  ;; range error leaking through a guard that was removed.
  (test-equal "um/mod by zero raises keel-error" 'keel-error
              (raised-key (lambda () (cell-um/mod 1 0 0))))
  (test-equal "um/mod quotient overflow raises keel-error" 'keel-error
              (raised-key (lambda () (cell-um/mod 0 1 1)))))

(define xs (samples 30))
(define ps (all-pairs xs))

(test-group "properties"
  (test-assert "+ is addition mod 2^32"
    (every (lambda (p) (= (cell+ (car p) (cdr p)) (modulo (+ (car p) (cdr p)) (expt 2 32)))) ps))
  (test-assert "+ is commutative"
    (every (lambda (p) (= (cell+ (car p) (cdr p)) (cell+ (cdr p) (car p)))) ps))
  (test-assert "nand is not-and"
    (every (lambda (p) (= (cell-nand (car p) (cdr p))
                          (- #xFFFFFFFF (logand (car p) (cdr p))))) ps))
  (test-assert "invert via nand: x nand x = ~x"
    (every (lambda (x) (= (cell-nand x x) (- #xFFFFFFFF x))) xs))
  (test-assert "0= only for zero"
    (every (lambda (x) (= (cell-0= x) (if (= x 0) #xFFFFFFFF 0))) xs))
  (test-assert "um* hi:lo equals exact product"
    (every (lambda (p) (receive (lo hi) (cell-um* (car p) (cdr p))
                         (= (+ lo (* hi (expt 2 32))) (* (car p) (cdr p))))) ps))
  (test-assert "um/mod: q*d + r = ud and r < d, for every ud = um* result"
    (every (lambda (p)
             (let ((d (if (zero? (cdr p)) 1 (cdr p))))
               (receive (lo hi) (cell-um* (car p) d)
                 (receive (r q) (cell-um/mod (cell+ lo 0) hi d)
                   (and (= (+ (* q d) r) (+ lo (* hi (expt 2 32)))) (< r d))))))
           ps)))

(define failed (test-runner-fail-count (test-runner-current)))
(test-end "cell")
(exit (if (zero? failed) 0 1))

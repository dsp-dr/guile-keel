;;; Tests for (keel outer): parsing, numbers, comments, headers, the host words.
(use-modules (keel cell) (keel vm) (keel outer) (srfi srfi-64))
(test-runner-current (test-runner-simple))
(define (stack-after src)
  (let ((vm (make-keel))) (interpret-string! vm src) (stack->list vm)))

(test-begin "outer")
(test-equal "numbers are pushed" '(1 -2 300) (stack-after "1 -2 300"))
(test-equal "hex via base" '(255) (stack-after "16 base ! ff"))
(test-equal "words are case-insensitive" '(3) (stack-after "1 2 +"))
(test-equal "backslash comment" '(1) (stack-after "1 \\ 2 3"))
(test-equal "paren comment" '(1 4) (stack-after "1 ( 2 3 ) 4"))
(test-error "undefined word" 'keel-error (stack-after "nosuchword"))
(test-error "number in a definition needs lit" 'keel-error (stack-after ": x 5 ;"))
(test-equal "colon definition from primitives" '(6) (stack-after ": add + ; 2 4 add"))
(test-equal "a word is hidden until ;" '(-1)
  (stack-after ": one 0= ; : one one ; 0 one"))   ; inner one is the old definition
(test-equal "redefinition shadows" '(-1) (stack-after ": z 0= ; : z z ; 0 z"))
;; The length byte carries five bits of name length. Nothing else in the tests
;; or in frames.fs has a name longer than 14 characters (resolve-leaves), so a
;; mask of 15 instead of 31 is otherwise indistinguishable.
(test-equal "a name of 16 characters is stored and found" '(7)
            (stack-after ": sixteen-char-nam + ; 3 4 sixteen-char-nam"))
(test-equal "a name of 31 characters, the maximum, is stored and found" '(7)
            (stack-after
             ": abcdefghijklmnopqrstuvwxyz01234 + ; 3 4 abcdefghijklmnopqrstuvwxyz01234"))
(test-equal "a name of 32 characters is refused" 'keel-error
            (catch #t
              (lambda ()
                (stack-after ": abcdefghijklmnopqrstuvwxyz012345 ;") 'no-error)
              (lambda (key . args) key)))
(let ((vm (make-keel)))
  (interpret-string! vm "create buf")
  (let ((xt (car (find-word vm "buf"))))
    (interpret-string! vm "buf")
    (test-equal "create pushes xt+8" (list (+ xt 8)) (stack->list vm))))
(let ((vm (make-keel)))
  (interpret-string! vm "' + ' +")
  (let ((s (stack->list vm)))
    (test-equal "' gives the same xt twice" (car s) (cadr s))
    (test-equal "' gives find-word's xt" (u32 (car s)) (car (find-word vm "+")))))
(let ((vm (make-keel)))
  ;; does> with an empty runtime: the child pushes its body address only
  (interpret-string! vm ": maker create does> ; maker child child")
  (let ((xt (car (find-word vm "child"))))
    (test-equal "does> child pushes its body" (list (+ xt 8)) (stack->list vm))))
(let ((vm (make-keel)))
  (interpret-string! vm ": maker create does> @ ; maker child")
  (interpret-string! vm "child")
  (test-equal "does> runs the code after does>" '(0) (stack->list vm)))
(test-assert "; is immediate"
  (let ((vm (make-keel))) (cdr (find-word vm ";"))))
(test-equal "state returns to 0 after ;" '(0) (stack-after ": x + ; state @"))

(define failed (test-runner-fail-count (test-runner-current)))
(test-end "outer")
(exit (if (zero? failed) 0 1))

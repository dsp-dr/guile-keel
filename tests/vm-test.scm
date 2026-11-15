;;; Tests for (keel vm): each primitive on hand-assembled threads, no frames.fs.
(use-modules (keel cell) (keel vm) (keel outer) (srfi srfi-1) (srfi srfi-64))
(test-runner-current (test-runner-simple))

(define (xt vm name) (car (or (find-word vm name) (error "no word" name))))
(define (assemble! vm name . items)
  "Colon definition NAME whose body is ITEMS: strings are words, integers raw cells."
  (interpret-string! vm (string-append ": " name))
  (for-each (lambda (it) (comma! vm (if (string? it) (xt vm it) (u32 it)))) items)
  (interpret-string! vm ";")
  (xt vm name))
(define (run vm stack . items)
  "Push STACK (bottom first), run a fresh thread of ITEMS, return the stack."
  (reset-stacks! vm)
  (for-each (lambda (x) (push! vm x)) stack)
  (run-xt! vm (apply assemble! vm "t" items))
  (stack->list vm))
(define (fresh) (make-keel))

(test-begin "vm")
(define vm (fresh))
(test-equal "+ wraps" '(0) (run vm (list #xFFFFFFFF 1) "+"))
(test-equal "nand" '(-1) (run vm '(0 5) "nand"))
(test-equal "0= true" '(-1) (run vm '(0) "0="))
(test-equal "0= false" '(0) (run vm '(9) "0="))
(test-equal "sp@ @ is dup" '(5 5) (run vm '(5) "sp@" "@"))
(test-equal "sp@ is the address of the top item" (list 5 (- s0 4)) (run vm '(5) "sp@"))
(test-equal "! then @" '(77) (run vm (list heap-start 77 heap-start) "!" "@"))
(test-equal "rp@ inside a colon word is r0-4" (list (- r0 4)) (run vm '() "rp@"))
(test-equal "rp@ @ is the caller's return address" (list a-scratch) (run vm '() "rp@" "@"))
(test-equal "exit stops the thread" '(7 7) (run vm '(7) "sp@" "@" "exit" "sp@" "@"))
(test-equal "execute runs an xt" '(9 9) (run vm (list 9 (xt vm "sp@")) "execute" "@"))
(test-equal "um*" '(1 -2) (run vm (list #xFFFFFFFF #xFFFFFFFF) "um*"))
(test-equal "um/mod" '(1 3) (run vm '(10 0 3) "um/mod"))

(let ((inner (assemble! vm "inner" "+")))
  (test-equal "nested colon call" '(5) (run vm '(2 3) "inner")))

(set-vm-in! vm (open-input-string "A"))
(test-equal "key reads a character" '(65) (run vm '() "key"))
(test-equal "key at end of input is -1" '(-1) (run vm '() "key"))
(let ((out (open-output-string)))
  (set-vm-out! vm out)
  (run vm '(66 67) "emit" "emit")
  (test-equal "emit writes characters" "CB" (get-output-string out))
  (set-vm-out! vm (current-output-port)))

(test-error "+ on an empty stack underflows" 'keel-error (run vm '() "+"))
(test-error "um/mod by zero" 'keel-error (run vm '(1 0 0) "um/mod"))
(test-error "@ outside memory" 'keel-error (run vm (list mem-size) "@"))

;; The guards below are checked by message, not merely by "something was
;; raised". Mutation testing showed that loosening a bounds test still leaves
;; an error coming out, just a different and later one: + pops twice, so an
;; off-by-one underflow check still trips on the second pop, and a read past
;; the top of memory still fails inside the bytevector rather than in the
;; guard. A single-pop primitive and a one-cell-wide overrun pin them down.
(define (raised-key thunk)
  (catch #t (lambda () (thunk) 'no-error) (lambda (key . args) key)))
(define (raised-msg thunk)
  (catch #t (lambda () (thunk) "no error")
    (lambda (key . args)
      (if (and (pair? args) (string? (car args))) (car args) (symbol->string key)))))

(test-equal "0= on an empty stack underflows on its only pop" "data stack underflow"
            (raised-msg (lambda () (run vm '() "0="))))
(test-equal "rpop! on an empty return stack underflows" "return stack underflow"
            (raised-msg (lambda () (let ((v (fresh))) (reset-stacks! v) (rpop! v)))))
(test-equal "@ one byte below the top of memory cannot read a whole cell" 'keel-error
            (raised-key (lambda () (run vm (list (- mem-size 1)) "@"))))
(test-equal "! one byte below the top of memory cannot write a whole cell" 'keel-error
            (raised-key (lambda () (run vm (list 7 (- mem-size 1)) "!"))))

;; emit must pass bytes 128-255 through unaltered; the output port is set to
;; ISO-8859-1 for exactly that reason. Every other emit test uses ASCII, so a
;; mask of 127 in place of 255 would go unnoticed.
(let ((out (open-output-string)))
  (set-vm-out! vm out)
  (run vm '(200 65) "emit" "emit")
  (test-equal "emit passes high-bit bytes through unaltered" '(65 200)
              (map char->integer (string->list (get-output-string out))))
  (set-vm-out! vm (current-output-port)))

;; The step budget must stop a runaway. The return stack holds 1024 cells, so
;; a budget well below that has to fire first; otherwise this only proves the
;; return-stack guard works, which a separate test already covers.
(let ((v (fresh)))
  (interpret-string! v ": forever")
  (let ((self (header>xt v (mem@ v a-latest))))
    (comma! v self)
    (interpret-string! v ";")
    (set-vm-steps! v 100)
    (test-equal "the step budget fires before the return stack fills" "step limit reached"
                (raised-msg (lambda () (run-xt! v self))))))
(let ((vm2 (fresh)))
  ;; a word that calls itself forever overflows the return stack
  (interpret-string! vm2 ": forever")
  (let ((self (header>xt vm2 (mem@ vm2 a-latest))))
    (comma! vm2 self)
    (interpret-string! vm2 ";")
    (test-error "unbounded recursion overflows the return stack" 'keel-error (run-xt! vm2 self))))

(define failed (test-runner-fail-count (test-runner-current)))
(test-end "vm")
(exit (if (zero? failed) 0 1))

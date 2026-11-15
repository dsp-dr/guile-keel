;;; (keel vm) -- memory, stacks and the inner interpreter.
;;;
;;; Memory is one 64 KiB little-endian bytevector. Both stacks live in it,
;;; so sp@ and rp@ return real addresses that @ and ! can use.
;;; Threading is indirect: a compiled cell holds an xt (the address of a
;;; code field); the code field holds a code number.
(define-module (keel vm)
  #:use-module (keel cell)
  #:use-module (rnrs bytevectors)
  #:use-module (srfi srfi-9)
  #:use-module (ice-9 format)
  #:export (;; layout
            mem-size a-state a->in a-#tib a-dp a-latest a-base a-scratch
            tib-start tib-size dict-start heap-start heap-end s-limit s0 r-limit r0
            ;; codes
            code-enter code-dovar code-docon code-halt code-dodoes
            primitive-codes host-codes
            ;; vm
            make-vm vm-mem vm-ip set-vm-ip! vm-sp set-vm-sp! vm-rp set-vm-rp!
            vm-in set-vm-in! vm-out set-vm-out! vm-host set-vm-host! vm-halt-xt set-vm-halt-xt!
            vm-steps set-vm-steps!
            mem@ mem! memc@ memc!
            push! pop! rpush! rpop! stack->list reset-stacks!
            run-xt!))

;;; ---- layout (byte addresses) -------------------------------------------
(define mem-size   #x10000)
(define a-state    0)       ; 0 = interpret, nonzero = compile
(define a->in      4)       ; offset of the next unparsed character in the TIB
(define a-#tib     8)       ; number of characters in the TIB
(define a-dp      12)       ; dictionary pointer (frames define: here = dp @)
(define a-latest  16)       ; header address of the newest definition
(define a-base    20)       ; number conversion radix
(define a-scratch 24)       ; 2 cells: thread used by run-xt!
(define tib-start 64)
(define tib-size  512)
(define dict-start 1024)
(define heap-start #x8000)  ; reserved for planking (two semispaces)
(define heap-end   #xE000)
(define s-limit    #xE000)  ; data stack: cells in [s-limit, s0), grows down
(define s0         #xF000)
(define r-limit    #xF000)  ; return stack: cells in [r-limit, r0), grows down
(define r0         #x10000)

;;; ---- code numbers ----------------------------------------------------------
(define code-enter  0)      ; colon definition: body at xt+4
(define code-dovar  1)      ; created word: push xt+8
(define code-docon  2)      ; constant: push cell at xt+4
(define code-halt   3)      ; stop run-xt!
(define code-dodoes 4)      ; created word after does>: push xt+8, run thread at mem[xt+4]

;; The 13 keel primitives, in spec order.
(define primitive-codes
  '(("@" . 16) ("!" . 17) ("sp@" . 18) ("rp@" . 19) ("0=" . 20) ("+" . 21)
    ("nand" . 22) ("exit" . 23) ("key" . 24) ("emit" . 25) ("execute" . 26)
    ("um*" . 27) ("um/mod" . 28)))

;; Bootstrap words that parse input or build headers. Implemented by the host.
(define host-codes
  '((":" . 32) (";" . 33) ("create" . 34) ("does>" . 35) ("'" . 36)))

;;; ---- the machine -------------------------------------------------------------
(define-record-type <vm>
  (%make-vm mem ip sp rp in out host halt-xt steps)
  vm?
  (mem vm-mem)
  (ip vm-ip set-vm-ip!)
  (sp vm-sp set-vm-sp!)
  (rp vm-rp set-vm-rp!)
  (in vm-in set-vm-in!)
  (out vm-out set-vm-out!)
  (host vm-host set-vm-host!)          ; (lambda (code vm) ...) for host-codes
  (halt-xt vm-halt-xt set-vm-halt-xt!)
  (steps vm-steps set-vm-steps!))      ; remaining instruction budget

(define (make-vm)
  (%make-vm (make-bytevector mem-size 0) 0 s0 r0
            (current-input-port) (current-output-port) #f 0 200000000))

(define (err fmt . args) (throw 'keel-error (apply format #f fmt args)))

;;; ---- memory -----------------------------------------------------------------
(define-inlinable (mem@ vm a)
  (unless (and (>= a 0) (<= (+ a 4) mem-size)) (err "@: address ~a out of range" a))
  (bytevector-u32-ref (vm-mem vm) a (endianness little)))
(define-inlinable (mem! vm a x)
  (unless (and (>= a 0) (<= (+ a 4) mem-size)) (err "!: address ~a out of range" a))
  (bytevector-u32-set! (vm-mem vm) a (u32 x) (endianness little)))
(define (memc@ vm a) (bytevector-u8-ref (vm-mem vm) a))
(define (memc! vm a c) (bytevector-u8-set! (vm-mem vm) a (logand c 255)))

;;; ---- stacks (memory-resident) -----------------------------------------------
(define-inlinable (push! vm x)
  (let ((sp (- (vm-sp vm) 4)))
    (when (< sp s-limit) (err "data stack overflow"))
    (mem! vm sp x)
    (set-vm-sp! vm sp)))
(define-inlinable (pop! vm)
  (let ((sp (vm-sp vm)))
    (when (>= sp s0) (err "data stack underflow"))
    (set-vm-sp! vm (+ sp 4))
    (mem@ vm sp)))
(define-inlinable (rpush! vm x)
  (let ((rp (- (vm-rp vm) 4)))
    (when (< rp r-limit) (err "return stack overflow"))
    (mem! vm rp x)
    (set-vm-rp! vm rp)))
(define-inlinable (rpop! vm)
  (let ((rp (vm-rp vm)))
    (when (>= rp r0) (err "return stack underflow"))
    (set-vm-rp! vm (+ rp 4))
    (mem@ vm rp)))

(define (stack->list vm)
  "Data stack, bottom first, as signed integers."
  (let loop ((a (- s0 4)) (acc '()))
    (if (< a (vm-sp vm)) (reverse acc) (loop (- a 4) (cons (s32 (mem@ vm a)) acc)))))

(define (reset-stacks! vm) (set-vm-sp! vm s0) (set-vm-rp! vm r0))

;;; ---- inner interpreter ------------------------------------------------------
;; Fetch the next xt from the thread and advance ip.
(define-inlinable (fetch! vm)
  (let ((ip (vm-ip vm)))
    (set-vm-ip! vm (+ ip 4))
    (mem@ vm ip)))

(define (run-xt! vm xt)
  "Execute XT and return when it finishes. The scratch thread holds the halt
word, so the outermost exit lands on it. The instruction budget is counted in
a local variable and written back when the run ends."
  (mem! vm a-scratch (vm-halt-xt vm))
  (set-vm-ip! vm a-scratch)
  (let loop ((w xt) (n (vm-steps vm)))
    (when (<= n 0) (set-vm-steps! vm 0) (err "step limit reached"))
    (case (mem@ vm w)
      ((0) (rpush! vm (vm-ip vm)) (set-vm-ip! vm (+ w 4)) (loop (fetch! vm) (- n 1)))   ; ENTER
      ((1) (push! vm (+ w 8)) (loop (fetch! vm) (- n 1)))                                 ; DOVAR
      ((2) (push! vm (mem@ vm (+ w 4))) (loop (fetch! vm) (- n 1)))                       ; DOCON
      ((3) (set-vm-steps! vm n))                                                          ; HALT
      ((4) (push! vm (+ w 8)) (rpush! vm (vm-ip vm))                                      ; DODOES
           (set-vm-ip! vm (mem@ vm (+ w 4))) (loop (fetch! vm) (- n 1)))
      ((16) (push! vm (mem@ vm (pop! vm))) (loop (fetch! vm) (- n 1)))                    ; @
      ((17) (let* ((a (pop! vm)) (x (pop! vm))) (mem! vm a x)) (loop (fetch! vm) (- n 1))) ; !
      ((18) (push! vm (vm-sp vm)) (loop (fetch! vm) (- n 1)))                             ; sp@
      ((19) (push! vm (vm-rp vm)) (loop (fetch! vm) (- n 1)))                             ; rp@
      ((20) (push! vm (cell-0= (pop! vm))) (loop (fetch! vm) (- n 1)))                    ; 0=
      ((21) (let* ((b (pop! vm)) (a (pop! vm))) (push! vm (cell+ a b))) (loop (fetch! vm) (- n 1)))     ; +
      ((22) (let* ((b (pop! vm)) (a (pop! vm))) (push! vm (cell-nand a b))) (loop (fetch! vm) (- n 1))) ; nand
      ((23) (set-vm-ip! vm (rpop! vm)) (loop (fetch! vm) (- n 1)))                        ; exit
      ((24) (let ((c (read-char (vm-in vm))))                                             ; key
              (push! vm (if (eof-object? c) cell-mask (char->integer c))))
            (loop (fetch! vm) (- n 1)))
      ((25) (write-char (integer->char (logand (pop! vm) 255)) (vm-out vm)) (loop (fetch! vm) (- n 1))) ; emit
      ((26) (loop (pop! vm) (- n 1)))                                                     ; execute
      ((27) (let* ((b (pop! vm)) (a (pop! vm)))                                           ; um*
              (call-with-values (lambda () (cell-um* a b))
                (lambda (lo hi) (push! vm lo) (push! vm hi))))
            (loop (fetch! vm) (- n 1)))
      ((28) (let* ((d (pop! vm)) (hi (pop! vm)) (lo (pop! vm)))                           ; um/mod
              (call-with-values (lambda () (cell-um/mod lo hi d))
                (lambda (r q) (push! vm r) (push! vm q))))
            (loop (fetch! vm) (- n 1)))
      ((32 33 34 35 36) ((vm-host vm) (mem@ vm w) vm) (loop (fetch! vm) (- n 1)))        ; host words
      (else (err "bad code ~a at xt ~a" (mem@ vm w) w)))))

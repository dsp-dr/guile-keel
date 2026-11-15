;;; (keel outer) -- dictionary, bootstrap words and the outer interpreter.
;;;
;;; Header layout, from the header address h:
;;;   h+0  link to the previous header (0 ends the list)
;;;   h+4  flags|length byte: bit 7 immediate, bit 6 hidden, bits 0-4 length
;;;   h+5  name bytes (stored lowercase), padded to a cell boundary
;;;   xt   code field; colon body starts at xt+4, created body at xt+8
;;;
;;; The host provides only what must parse input or build headers:
;;; : ; create does> '  and the comment syntax \ and ( .
;;; Everything else is defined in forth/frames.fs from the 13 primitives.
(define-module (keel outer)
  #:use-module (keel cell)
  #:use-module (keel vm)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 format)
  #:use-module (srfi srfi-1)
  #:export (make-keel find-word interpret-line! interpret-string! load-file! make-header!
            header>xt here set-here! comma!))

(define flag-immediate 128)
(define step-budget                 ; instructions per top-level word; KEEL_STEPS overrides
  (let ((e (getenv "KEEL_STEPS"))) (if e (string->number e) 200000000)))
(define flag-hidden 64)

(define (err fmt . args) (throw 'keel-error (apply format #f fmt args)))

(define (here vm) (mem@ vm a-dp))
(define (set-here! vm a) (mem! vm a-dp a))
(define (comma! vm x) (let ((h (here vm))) (mem! vm h x) (set-here! vm (+ h 4))))
(define (align a) (logand (+ a 3) (lognot 3)))

(define (header>xt vm h)
  (align (+ h 5 (logand (memc@ vm (+ h 4)) 31))))

(define (make-header! vm name code)
  "Lay down a header for NAME with CODE in its code field; return the header address."
  (let* ((name (string-downcase name))
         (n (string-length name))
         (h (align (here vm))))
    (when (> n 31) (err "name too long: ~a" name))
    (mem! vm h (mem@ vm a-latest))
    (memc! vm (+ h 4) n)
    (string-for-each-index (lambda (i) (memc! vm (+ h 5 i) (char->integer (string-ref name i)))) name)
    (let ((xt (align (+ h 5 n))))
      (mem! vm xt code)
      (set-here! vm (+ xt 4))
      (mem! vm a-latest h)
      h)))

(define (string-for-each-index f s)
  (let loop ((i 0)) (when (< i (string-length s)) (f i) (loop (+ i 1)))))

(define (header-name vm h)
  (let ((n (logand (memc@ vm (+ h 4)) 31)))
    (list->string (map (lambda (i) (integer->char (memc@ vm (+ h 5 i)))) (iota n)))))

(define (find-word vm name)
  "Return (xt . immediate?) for the newest visible definition of NAME, or #f."
  (let ((name (string-downcase name)))
    (let loop ((h (mem@ vm a-latest)))
      (cond ((zero? h) #f)
            ((and (zero? (logand (memc@ vm (+ h 4)) flag-hidden))
                  (= (logand (memc@ vm (+ h 4)) 31) (string-length name))
                  (string=? (header-name vm h) name))
             (cons (header>xt vm h) (not (zero? (logand (memc@ vm (+ h 4)) flag-immediate)))))
            (else (loop (mem@ vm h)))))))

;;; ---- parsing from the TIB in memory ---------------------------------------
(define (tib-char vm i) (integer->char (memc@ vm (+ tib-start i))))

(define (parse-name! vm)
  "Skip spaces, return the next space-delimited token (or \"\"), leave >in after its delimiter."
  (let ((n (mem@ vm a-#tib)))
    (let skip ((i (mem@ vm a->in)))
      (if (and (< i n) (char-whitespace? (tib-char vm i)))
          (skip (+ i 1))
          (let scan ((j i))
            (if (and (< j n) (not (char-whitespace? (tib-char vm j))))
                (scan (+ j 1))
                (begin
                  (mem! vm a->in (min n (+ j 1)))
                  (list->string (map (lambda (k) (tib-char vm k)) (iota (- j i) i))))))))))

(define (skip-past! vm ch)
  (let ((n (mem@ vm a-#tib)))
    (let loop ((i (mem@ vm a->in)))
      (cond ((>= i n) (mem! vm a->in n))
            ((char=? (tib-char vm i) ch) (mem! vm a->in (+ i 1)))
            (else (loop (+ i 1)))))))

(define (parse-number vm s)
  "Signed integer in the current base, as a cell, or #f."
  (let* ((base (mem@ vm a-base))
         (neg (and (> (string-length s) 1) (char=? (string-ref s 0) #\-)))
         (digits (if neg (substring s 1) s)))
    (and (> (string-length digits) 0)
         (let loop ((cs (string->list digits)) (acc 0))
           (if (null? cs)
               (u32 (if neg (- acc) acc))
               (let* ((c (char-downcase (car cs)))
                      (d (cond ((char-numeric? c) (- (char->integer c) 48))
                               ((char-alphabetic? c) (+ 10 (- (char->integer c) 97)))
                               (else 99))))
                 (and (< d base) (loop (cdr cs) (+ (* acc base) d)))))))))

;;; ---- host words -------------------------------------------------------------
(define (host-word code vm)
  (case code
    ((32) (let ((name (parse-name! vm)))                                   ; :
            (when (string-null? name) (err ": needs a name"))
            (let ((h (make-header! vm name code-enter)))
              (memc! vm (+ h 4) (logior (memc@ vm (+ h 4)) flag-hidden))
              (mem! vm a-state true-flag))))
    ((33) (comma! vm (car (or (find-word vm "exit") (err "exit missing"))))  ; ;
          (let ((h (mem@ vm a-latest)))
            (memc! vm (+ h 4) (logand (memc@ vm (+ h 4)) (lognot flag-hidden))))
          (mem! vm a-state 0))
    ((34) (let ((name (parse-name! vm)))                                   ; create
            (when (string-null? name) (err "create needs a name"))
            (make-header! vm name code-dovar)
            (comma! vm 0)))                                                ; does> slot
    ((35) (let ((xt (header>xt vm (mem@ vm a-latest))))                    ; does>
            (mem! vm xt code-dodoes)
            (mem! vm (+ xt 4) (vm-ip vm))
            (set-vm-ip! vm (rpop! vm))))
    ((36) (let* ((name (parse-name! vm))                                   ; '
                 (w (find-word vm name)))
            (unless w (err "' : ~a is undefined" name))
            (push! vm (car w))))))

;;; ---- bootstrap ----------------------------------------------------------------
(define (make-keel)
  (let ((vm (make-vm)))
    (set-vm-host! vm host-word)
    (mem! vm a-dp dict-start)
    (mem! vm a-latest 0)
    (mem! vm a-base 10)
    (mem! vm a-state 0)
    (for-each (lambda (p) (make-header! vm (car p) (cdr p))) primitive-codes)
    (for-each (lambda (p) (make-header! vm (car p) (cdr p))) host-codes)
    (let ((semi (find-word vm ";")))                    ; ; is immediate
      (let loop ((h (mem@ vm a-latest)))
        (if (= (header>xt vm h) (car semi))
            (memc! vm (+ h 4) (logior (memc@ vm (+ h 4)) flag-immediate))
            (loop (mem@ vm h)))))
    (for-each (lambda (p)                                ; system constants
                (make-header! vm (car p) code-docon)
                (comma! vm (cdr p)))
              `(("state" . ,a-state) (">in" . ,a->in) ("#tib" . ,a-#tib) ("dp" . ,a-dp)
                ("latest" . ,a-latest) ("base" . ,a-base) ("tib" . ,tib-start) ("s0" . ,s0)
                ("heap-start" . ,heap-start) ("heap-end" . ,heap-end)))
    (let ((h (make-header! vm "(halt)" code-halt)))
      (memc! vm (+ h 4) (logior (memc@ vm (+ h 4)) flag-hidden))
      (set-vm-halt-xt! vm (header>xt vm h)))
    vm))

;;; ---- outer interpreter ----------------------------------------------------------
(define (interpret-line! vm line)
  (let ((n (min (string-length line) tib-size)))
    (string-for-each-index (lambda (i) (memc! vm (+ tib-start i) (char->integer (string-ref line i))))
                           (substring line 0 n))
    (mem! vm a-#tib n)
    (mem! vm a->in 0))
  (let loop ()
    (let ((tok (parse-name! vm)))
      (unless (string-null? tok)
        (cond
         ((string=? tok "\\") (mem! vm a->in (mem@ vm a-#tib)))
         ((string=? tok "(") (skip-past! vm #\)))
         ((find-word vm tok)
          => (lambda (w)
               (if (or (zero? (mem@ vm a-state)) (cdr w))
                   (begin (set-vm-steps! vm step-budget) (run-xt! vm (car w)))
                   (comma! vm (car w)))))
         ((parse-number vm tok)
          => (lambda (x)
               (if (zero? (mem@ vm a-state))
                   (push! vm x)
                   (let ((lit (find-word vm "lit")))
                     (unless lit (err "number ~a in a definition before lit is defined" tok))
                     (comma! vm (car lit))
                     (comma! vm x)))))
         (else (err "~a is undefined" tok)))
        (loop)))))

(define (interpret-string! vm s)
  (for-each (lambda (line) (interpret-line! vm line)) (string-split s #\newline)))

(define (load-file! vm path)
  "Interpret PATH line by line. On error, print it with the line number and rethrow."
  (call-with-input-file path
    (lambda (port)
      (set-port-encoding! port "ISO-8859-1")
      (let loop ((lineno 1))
        (let ((line (read-line port)))
          (unless (eof-object? line)
            (catch 'keel-error
              (lambda () (interpret-line! vm line))
              (lambda (key msg)
                (throw 'keel-error (format #f "~a:~a: ~a" path lineno msg))))
            (loop (+ lineno 1))))))))

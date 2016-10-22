#lang racket

(require "../common.rkt")
(require "../alternative.rkt")
(require "../programs.rkt")
(require "../syntax/distributions.rkt")

(provide (struct-out test) test-program test-samplers
         load-tests load-file test-target parse-test unparse-test test-successful? test<?)

(define (test-program test)
  `(λ ,(test-vars test) ,(test-input test)))

(define (test-target test)
  `(λ ,(test-vars test) ,(test-output test)))

(define (test-successful? test input-bits target-bits output-bits)
  (match* ((test-output test) (test-expected test))
    [(_ #f) #t]
    [(_ (? number? n)) (>= n output-bits)]
    [(#f #t) (>= input-bits output-bits)]
    [(_ #t) (>= target-bits (- output-bits 1))]))

(struct test (name vars sampling-expr input output expected precondition) #:prefab)

(define (test-samplers test)
  (for/list ([var (test-vars test)] [samp (test-sampling-expr test)])
    (cons var (eval-sampler samp))))

(define (parse-test expr)
  (match expr
    [(list 'FPCore (list args ...) props ... body)
     (define prop-dict
       (let loop ([props props] [out '()])
         (if (null? props)
             out
             (loop (cddr props) (cons (cons (first props) (second props)) out)))))
     (define samp-dict (dict-ref prop-dict ':herbie-samplers '()))
     (define samps (map (lambda (x) (car (dict-ref samp-dict x '(default)))) args))

     (define body* (desugar-program body))

     (when (not (valid-expression? body* args))
       (raise-user-error 'parse-input "Invalid program body ~a.\nSee <http://herbie.uwplse.org/doc/~a/faq.html#invalid-program> for more." expr *herbie-version*))

     (test (~a (dict-ref prop-dict ':name body))
           args samps
           body*
           (desugar-program (dict-ref prop-dict ':target #f))
           (dict-ref prop-dict ':herbie-expected #t)
           (dict-ref prop-dict ':pre 'TRUE))]
    [(list (or 'λ 'lambda 'define 'herbie-test) _ ...)
     (raise-user-error 'parse-input "Herbie 1.0+ no longer supports input formats other than FPCore.\nSee <http://herbie.uwplse.org/~a/input.html> for more." *herbie-version*)]
    [_
     (raise-user-error 'parse-input "Invalid input expression.\nSee <http://herbie.uwplse.org/~a/input.html> for more." *herbie-version*)]))

(define (unparse-test expr)
  (match-define (list (or 'λ 'lambda) (list vars ...) body) expr)
  `(FPCore (,@vars) ,body))

(define (load-file file)
  (call-with-input-file file
    (λ (port)
      (define tests (for/list ([test (in-port read port)])
                      (parse-test test)))
      (let ([duplicate-name (check-duplicates tests #:key test-name)])
        (assert (not duplicate-name)
                #:extra-info (λ () (format "Two tests with the same name ~a" duplicate-name))))
      tests)))

(define (is-racket-file? f)
  (and (equal? (filename-extension f) #"fpcore") (file-exists? f)))

(define (load-directory dir)
  (for/append ([fname (in-directory dir)] #:when (is-racket-file? fname))
    (load-file fname)))

(define (load-tests [path benchmark-path])
  (if (directory-exists? path)
      (load-directory path)
      (load-file path)))

(define (test<? t1 t2)
  (cond
   [(and (test-output t1) (test-output t2))
    (string<? (test-name t1) (test-name t2))]
   [(and (not (test-output t1)) (not (test-output t2)))
    (string<? (test-name t1) (test-name t2))]
   [else
    ; Put things with an output first
    (test-output t1)]))
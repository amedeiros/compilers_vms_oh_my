;; Require a ruby library can raise LoadError
(define rb-require (lambda (x) (rb-class-call "require" "Kernel" x)))

;; Create a ruby constant from a string
(define constantize (lambda (x) (rb-call "constantize" x)))

;; ruby is_a?
(define is_a? (lambda (x y) (rb-call "is_a?" x (constantize y))))

;; Make sure a list is a list by wrapping it
(define array->wrap (lambda (x)
  (rb-class-call "wrap" "Array" x)))

;; Builtin list length
(define list->len (lambda (x)
  (rb-call "size" x)))

;; Builtin car
(define car (lambda (x)
  (rb-call "shift" x)))

;; Builtin cdr
(define cdr (lambda (x)
  (if (= 2 (list->len (array->wrap x)))
    (array->wrap (rb-call "at" x 1))
    (array->wrap
      (rb-call "values_at" x (rb-class-call "new" "Range" 1 (- (list->len x) 1)))))))

;; Builtin cons
(define cons (lambda (x y)
  (rb-call "unshift" (array->wrap y) x )))

;; Builtin not
(define not (lambda (x)
  (= #f x)))

;; Builtin and
(define and (lambda (x y)
  (if x
    (if y
      #t
      #f)
    #f
    )))

;; Builtin or
(define or (lambda (x y)
  (if x
    #t
    (if y
      #t
      #f))))

;; to-sxp for the repl
(define to-sxp (lambda (x)
  (rb-call "to_sxp" x)))

;; Builtin atom?
(define atom? (lambda (x) (not (is_a? x "Array"))))

;; Builtin null?
(define null? (lambda (x)
  (if (is_a? x "Array")
    (rb-call "empty?" x)
    #f)))

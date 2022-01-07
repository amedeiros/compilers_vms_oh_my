;; A file where I can write code to compile and test

(define and (lambda (x y)
  (if x
    (if y
      #t
      #f)
    #f)))

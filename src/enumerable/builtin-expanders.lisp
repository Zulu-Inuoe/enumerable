(in-package #:enumerable)

;;; SBCL will make use of sb-sequence:do-sequence
#-sbcl
(progn
  (define-do-enumerable-expander list
      (type var enumerable result body env)
    `(dolist (,var ,enumerable ,@(when result `(,result)))
       ,@body))

  (define-do-enumerable-expander vector
      (type var enumerable result body env)
    (with-gensyms (vec i)
      (multiple-value-bind (body decls)
          (parse-body body)
        `(let ((,vec ,enumerable))
           (dotimes (,i (length ,vec) ,@(when result `((let (,var) ,var ,result))))
             (let ((,var (aref ,vec ,i)))
               ,@decls
               (tagbody ,@body))))))))

#+sbcl
(define-do-enumerable-expander sequence
    (type var enumerable result body env)
  `(sb-sequence:dosequence (,var ,enumerable ,@(when result `(,result)))
     ,@body))

(define-do-enumerable-expander hash-table
    (type var enumerable result body env)
  (with-gensyms (iter more? key value)
    (multiple-value-bind (body decls)
        (parse-body body)
      `(with-hash-table-iterator (,iter ,enumerable)
         (do ()
             (nil)
           (multiple-value-bind (,more? ,key ,value)
               (,iter)
             (unless ,more?
               (return ,@(when result `((let (,var) ,var ,result)))))
             (let ((,var (cons ,key ,value)))
               ,@decls
               (tagbody ,@body))))))))

(define-do-enumerable-expander stream
    (type var enumerable result body env)
  (with-gensyms (enum-sym elt-sym)
    (multiple-value-bind (body decls)
        (parse-body body)
      `(let ((,enum-sym ,enumerable))
         (cond
           ((subtypep (stream-element-type ,enum-sym) 'integer)
            (do ((,elt-sym (read-byte ,enum-sym nil nil) (read-byte ,enum-sym nil nil)))
                ((null ,elt-sym) ,@(when result `((let (,var) ,var ,result))))
              (let ((,var ,elt-sym))
                ,@decls
                (tagbody ,@body))))
           ((subtypep (stream-element-type ,enum-sym) 'character)
            (do ((,elt-sym (read-char ,enum-sym nil nil) (read-char ,enum-sym nil nil)))
                ((null ,elt-sym) ,@(when result `((let (,var) ,var ,result))))
              (let ((,var ,elt-sym))
                ,@decls
                (tagbody ,@body))))
           (t (error "unsupported stream type '~A'" (stream-element-type ,enum-sym))))))))

(define-do-enumerable-expander lazy-seq
    (type var enumerable result body env)
  (with-gensyms (seq-sym)
    (multiple-value-bind (body decls)
        (parse-body body)
      `(do ((,seq-sym (col-seq ,enumerable) (col-seq (seq-rest ,seq-sym))))
           ((null ,seq-sym) ,@(when result `((let (,var) ,var ,result))))
         (let ((,var (seq-first ,seq-sym)))
           ,@decls
           (tagbody ,@body))))))

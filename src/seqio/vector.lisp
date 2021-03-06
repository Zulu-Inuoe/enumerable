(in-package #:com.inuoe.seqio)

;; Optimizations for vectors since they allow fast random access

(defun %make-collapsed-displaced-vector (vec offset count)
  (check-type offset array-index)
  (check-type count array-length)
  (labels ((recurse (vec offset count)
             (check-type vec vector)
             (multiple-value-bind (displaced-to displaced-offset) (array-displacement vec)
               (cond
                 (displaced-to
                  (recurse displaced-to (+ offset displaced-offset) count))
                 ((= count (length vec))
                  vec)
                 (t
                  (make-array count :element-type (array-element-type vec) :displaced-to vec :displaced-index-offset offset))))))
    (recurse vec offset count)))

(defmethod any* ((col vector) predicate)
  (and (position-if predicate col) t))

(defmethod batch ((col vector) size &key (element-type (array-element-type col)) adjustable fill-pointer-p)
  (labels ((recurse (pos e-len)
             (when (< pos e-len)
               (let ((len (min size (- e-len pos))))
                 (cons
                  (replace (make-array len :element-type element-type :adjustable adjustable :fill-pointer (and fill-pointer-p t))
                           col
                           :start2 pos)
                  (lazy-seq (recurse (+ pos size) e-len)))))))
    (lazy-seq (recurse 0 (length col)))))

(defmethod consume ((col vector))
  (values))

(defmethod contains ((col vector) item &optional (test #'eql))
  (position item col :test test))

(defmethod element-at ((col vector) index &optional default)
  (if (< index (length col))
      (aref col index)
      default))

(defmethod elast ((col vector) &optional default)
  (let ((len (length col)))
    (cond
      ((zerop len) default)
      (t (aref col (1- len))))))

(defmethod elast* ((col vector) predicate &optional default)
  (if-let ((pos (position-if predicate col :from-end t)))
    (aref col pos)
    default))

(defmethod pad ((col vector) width &optional padding)
  (check-type width (integer 0))
  (let ((len (length col)))
    (if (<= width len)
        col
        (labels ((yield-col (i)
                   (if (< i len)
                       (cons (aref col i)
                             (lazy-seq (yield-col (1+ i))))
                       (yield-padding i)))
                 (yield-padding (i)
                   (when (< i width)
                     (cons padding (lazy-seq (yield-padding (1+ i)))))))
          (lazy-seq (yield-col 0))))))

(defmethod pad* ((col vector) width &optional padding-selector
                 &aux (padding-selector (or padding-selector #'identity)))
  (check-type width (integer 0))
  (let ((len (length col)))
    (if (<= width len)
        col
        (labels ((yield-col (i)
                   (if (< i len)
                       (cons (aref col i)
                             (lazy-seq (yield-col (1+ i))))
                       (yield-padding i)))
                 (yield-padding (i)
                   (when (< i width)
                     (cons (funcall padding-selector i)
                           (lazy-seq (yield-padding (1+ i)))))))
          (lazy-seq (yield-col 0))))))

(defmethod ereverse ((col vector))
  (labels ((recurse (i)
             (when (>= i 0)
               (lazy-seq
                 (cons (aref col i)
                       (recurse (1- i)))))))
    (recurse (1- (length col)))))

(defmethod single ((col vector) &optional default)
  (let ((len (length col)))
    (cond
      ((> len 1) (error "more than one element present in the col"))
      ((= len 1) (aref col 0))
      (t default))))

(defmethod single* ((col vector) predicate &optional default)
  (loop
    :with found-value := nil
    :with ret := default
    :for elt :across col
    :if (funcall predicate elt)
      :do (if found-value
              (error "more than one element present in the col matches predicate")
              (setf found-value t
                    ret elt))
    :finally (return ret)))

(defmethod skip ((col vector) count)
  (if (<= count 0)
      col
      (let ((len (length col)))
        (if (<= len count)
            nil
            (%make-collapsed-displaced-vector col count (- len count))))))

(defmethod skip-last ((col vector) count)
  (if (<= count 0)
      col
      (let ((len (length col)))
        (if (<= len count)
            nil
            (%make-collapsed-displaced-vector col 0 (- len count))))))

(defmethod skip-until ((col vector) predicate)
  (lazy-seq
    (when-let ((start (position-if predicate col)))
      (%make-collapsed-displaced-vector col start (- (length col) start)))))

(defmethod skip-while ((col vector) predicate)
  (lazy-seq
    (when-let ((start (position-if-not predicate col)))
      (%make-collapsed-displaced-vector col start (- (length col) start)))))

(defmethod take ((col vector) count)
  (cond
    ((<= count 0)
     nil)
    ((<= (length col) count)
     col)
    (t
     (%make-collapsed-displaced-vector col 0 count))))

(defmethod take-last ((col vector) count)
  (when (minusp count)
    (error "count cannot be negative, was ~A" count))
  (if (zerop count)
      nil
      (let ((len (length col)))
        (if (>= count len)
            col
            (%make-collapsed-displaced-vector col (- len count) count)))))

(defmethod window ((col vector) size &key (element-type (array-element-type col)) adjustable fill-pointer-p)
  (let ((len (length col)))
    (cond
      ((< len size)
       nil)
      ((= len size)
       (list (make-array size :initial-contents col
                              :element-type element-type
                              :adjustable adjustable
                              :fill-pointer (and fill-pointer-p t))))
      (t
       (labels ((recurse (i end-idx)
                  (unless (> i end-idx)
                    (lazy-seq
                      (cons
                       (replace (make-array size :element-type element-type
                                                 :adjustable adjustable
                                                 :fill-pointer (and fill-pointer-p t))
                                col
                                :start2 i)
                       (recurse (1+ i) end-idx))))))
         (recurse 0 (- len size)))))))

(defmethod to-vector ((col vector) &key (element-type (array-element-type col)) adjustable fill-pointer-p)
  (make-array (length col)
              :element-type element-type
              :initial-contents col
              :adjustable adjustable
              :fill-pointer (and fill-pointer-p t)))

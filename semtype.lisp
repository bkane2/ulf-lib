;; Data structures for representing ULF semantic types

(in-package :ulf-lib)

;; Class representing a ULF semantic type
(defclass semtype ()
  ((domain
     :initarg :domain
     :accessor domain)
   (range
     :initarg :range
     :initform nil
     :accessor range)
   (exponent
     :initarg :ex
     :initform 1
     :accessor ex)
   (subscript
     :initarg :subscript
     :initform nil
     :accessor subscript)
   (tense
     :initarg :tense
     :initform nil
     :accessor tense)))

;; Subclass for atomic types
(defclass atomic-type (semtype)
  ())

;; Type to represent "{A|B}"
;; Currently only supports two options
(defclass optional-type (semtype)
  ((types
     :initarg :types
     :accessor types)))

;; Check if a given object is a semtype
(defun semtype-p (s)
  (equal (type-of s) 'semtype))

;; Check if a given object is an atomic-type.
(defun atomic-type-p (s)
  (equal (type-of s) 'atomic-type))

;; Check if a given object is an optional-type.
(defun optional-type-p (s)
  (equal (type-of s) 'optional-type))

;; Create a new ULF type as an instance of the appropriate class.
;; If :options is specified, an optional type is created.
;; If ran is NIL an atomic type is created.
;; Rigorous sanity checking is NOT done, so unexpected inputs might cause
;; unexpected outputs.
;;
;; Types with a variable for an exponent are expanded out into a chain of
;; optionals where the variable value lies between 0 and 6. For example, A^n would
;; become {A^0|{A^1|{A^2|...}}}.
(defun new-semtype (dom ran exponent sub ten &key options)
  (progn
    (setf dom (copy-semtype dom))
    (setf ran (copy-semtype ran))
    (setf options (mapcar #'copy-semtype options))
    (if (not (numberp exponent))
      ; The exponent is not a number
      (if (listp exponent)
        ; If the exponent is a list, we are currently recursing to form a chain of
        ; optionals
        (if (= (length exponent) 1)
          (new-semtype dom ran (car exponent) sub ten :options options)
          (new-semtype NIL NIL 1 NIL NIL
                       :options (list (new-semtype dom ran (car exponent) sub ten :options options)
                                      (new-semtype dom ran (cdr exponent) sub ten :options options))))
        ; If the exponent is not a number or a list, treat it as a variable and
        ; start recursion to form a chain of optionals
        (new-semtype dom ran '(0 1 2 3 4 5) sub ten :options options))
  
      ; Unless the exponent is 0 (in which case the type is NIL), create the type
      (unless (= exponent 0)
        (if options
          ; Create optional type
          (make-instance 'optional-type
                         :types options
                         :ex exponent
                         :subscript sub
                         :tense ten)
  
          ; If the type isn't an optional, check if range is non-NIL
          (if ran
            ; Range is not NIL
            (if (and (optional-type-p dom) (= (ex dom) 1))
              ; The domain is optional. Push the range in. For example, {A|B}=>C
              ; would become {(A=>C)|(B=>C)}. This is convenient for composition
              ; functions.
              (make-instance 'optional-type
                             :types (list (new-semtype (car (types dom)) ran 1 sub ten)
                                          (new-semtype (cadr (types dom)) ran 1 sub ten)))
  
              ; The domain is not optional
              (if dom
                ; Create new semtype
                (make-instance 'semtype
                               :domain dom
                               :range ran
                               :ex exponent
                               :subscript sub
                               :tense ten)
                ; If the domain is NIL, return the range
                (progn
                  (setf (ex ran) exponent)
                  (setf (subscript ran) sub)
                  (setf (tense ran) ten)
                  ran)))
    
            ; Range is NIL; the type is atomic.
            (make-instance 'atomic-type
                           :domain dom
                           :ex exponent
                           :subscript sub
                           :tense ten)))))))

;; Check if two semantic types are equal. If one of the types is an optional
;; type then return true of either of the two options match. If both types are
;; optional they must contain the same options (order doesn't matter).
;; If :ignore-exp is not NIL then exponents of the two types aren't checked
;; If :ignore-exp is 'r then ignore exponents recursively
;; Tenses and subscripts are checked if both types have a specified
;; tense/subscript.
;; Tenses and subscripts on optionals are ignored.
;;
;; Note: This function is more of a "compatibility checker" than a function to
;; check actual equality. I'll probably rename this to something better later.
(defun semtype-equal? (x y &key ignore-exp)
  (if (or (optional-type-p x) (optional-type-p y))
    ;; At least one optional
    (if (and (optional-type-p x) (optional-type-p y))
      ;; Both optional
      (when (if ignore-exp T (equal (ex x) (ex y)))
        (let ((A (car (types x))) (B (cadr (types x))) (C (car (types y))) (D (cadr (types y))))
          (or (and (semtype-equal? A C :ignore-exp (when (equal ignore-exp 'r) 'r))
                   (semtype-equal? B D :ignore-exp (when (equal ignore-exp 'r) 'r)))
              (and (semtype-equal? A D :ignore-exp (when (equal ignore-exp 'r) 'r))
                   (semtype-equal? B C :ignore-exp (when (equal ignore-exp 'r) 'r))))))

      (if (optional-type-p x)
        ;; x optional; y not optional
        (or (and (or (= (ex y) (* (ex (car (types x))) (ex x))) ignore-exp)
                 (semtype-equal? y (car (types x)) :ignore-exp (if (equal ignore-exp 'r) 'r T)))
            (and (or (= (ex y) (* (ex (cadr (types x))) (ex x))) ignore-exp)
                 (semtype-equal? y (cadr (types x)) :ignore-exp (if (equal ignore-exp 'r) 'r T))))
        ;; y optional; x not optional
        (or (and (or (= (ex x) (* (ex (car (types y))) (ex y))) ignore-exp)
                 (semtype-equal? x (car (types y)) :ignore-exp (if (equal ignore-exp 'r) 'r T)))
            (and (or (= (ex x) (* (ex (cadr (types y))) (ex y))) ignore-exp)
                 (semtype-equal? x (cadr (types y)) :ignore-exp (if (equal ignore-exp 'r) 'r T))))))
    
    ;; No optionals
    (when (and (if ignore-exp T (equal (ex x) (ex y)))
               (equal (type-of x) (type-of y))
               (if (and (subscript x) (subscript y)) (equal (subscript x) (subscript y)) T)
               (equal (tense x) (tense y)))
      (if (atomic-type-p x)
        (equal (domain x) (domain y))
        (and (semtype-equal? (domain x) (domain y) :ignore-exp (when (equal ignore-exp 'r) 'r))
             (semtype-equal? (range x) (range y) :ignore-exp (when (equal ignore-exp 'r) 'r)))))))

;; Make a new semtype identical to the given type
(defun copy-semtype (x)
  (if (or (semtype-p x) (atomic-type-p x) (optional-type-p x))
    (if (atomic-type-p x)
      (make-instance 'atomic-type
                     :domain (domain x)
                     :ex (ex x)
                     :subscript (subscript x)
                     :tense (tense x))
      (if (optional-type-p x)
        (make-instance 'optional-type
                       :types (list (copy-semtype (car (types x))) (copy-semtype (cadr (types x))))
                       :ex (ex x)
                       :subscript (subscript x)
                       :tense (tense x))
        (make-instance 'semtype
                     :domain (copy-semtype (domain x))
                     :range (copy-semtype (range x))
                     :ex (ex x)
                     :subscript (subscript x)
                     :tense (tense x))))
    x))

;; Convert a semtype to a string. The string it returns can be read back into a
;; type using str2semtype.
(defun semtype2str (s)
  (when (or (semtype-p s) (atomic-type-p s) (optional-type-p s))
    (if (atomic-type-p s)
      ; Atomic type
      (format nil "~a~a~a~a"
              (domain s)
              (if (subscript s) (format nil "_~a" (subscript s)) "")
              (if (tense s) (format nil "_~a" (tense s)) "")
              (if (= (ex s) 1) "" (format nil "^~a" (ex s))))
      ; Non-atomic type
      (if (optional-type-p s)
        ; Optional type
        (format nil "{~a|~a}~a"
                (semtype2str (car (types s)))
                (semtype2str (cadr (types s)))
                (if (= (ex s) 1) "" (format nil "^~a" (ex s))))
        ; Not optional or atomic
        (format nil "(~a=>~a)~a~a~a"
                (semtype2str (domain s))
                (semtype2str (range s))
                (if (subscript s) (format nil "_~a" (subscript s)) "")
                (if (tense s) (format nil "_~a" (tense s)) "")
                (if (= (ex s) 1) "" (format nil "^~a" (ex s))))))))

;; Split a string of the form ([domain]=>[range]) into [domain] and [range].
;; Helper for str2semtype.
(defun split-semtype-str (s)
  (let ((level 0) (i 1))
    (loop
      (when (equal (char s i) #\()
        (setf level (+ level 1)))
      (when (equal (char s i) #\))
        (setf level (- level 1)))
      (when (and (equal (char s i) #\=) (= level 0))
        (return i))
      (setf i (+ i 1)))
    (list (subseq s 1 i) (subseq s (+ i 2) (- (length s) 1)))))

;; Split a string of the form {A|B} into A and B. Helper for str2semtype.
(defun split-opt-str (s)
  (let ((level 0) (i 1))
    (loop
      (when (equal (char s i) #\{)
        (setf level (+ level 1)))
      (when (equal (char s i) #\})
        (setf level (- level 1)))
      (when (and (equal (char s i) #\|) (= level 0))
        (return i))
      (setf i (+ i 1)))
    (list (subseq s 1 i) (subseq s (+ i 1) (- (length s) 1)))))

;; Convert a string into a semantic type.
;; Strings must be of the form ([domain]=>[range]) or a single character, where
;; [domain] and [range] are valid strings of the same form.
;; Some single character subscripts are supported, denoted by a _ followed
;; by the character. Single digit/character exponents are also supported
;; denoted by a ^ followed by the digit/character. Exponents must occur after
;; any subscripts.
(defun str2semtype (s)
  (progn
    (setf s (string-upcase s))
    (if (equal (char s 0) #\()
      ; NON ATOMIC ([domain]=>[range])_[ut|navp]^n
      (let ((match (nth-value 1 (cl-ppcre:scan-to-strings
                                  "^(\\(.*\\))(_(([UT])|([NAVP])))?(\\^([A-Z]|[2-9]))?$"
                                  s))))
        (new-semtype (str2semtype (car (split-semtype-str (svref match 0))))
                     (str2semtype (cadr (split-semtype-str (svref match 0))))
                     (if (svref match 6) (read-from-string (svref match 6)) 1)
                     (if (svref match 4) (read-from-string (svref match 4)) nil)
                     (if (svref match 3) (read-from-string (svref match 3)) nil)))
  
      ; ATOMIC or OPTIONAL
      (if (equal (char s 0) #\{)
        ; OPTIONAL {A|B}
        (let ((match (nth-value 1 (cl-ppcre:scan-to-strings
                                    "^(\\{.*\\})(_(([UT])|([NAVP])))?(\\^([A-Z]|[2-9]))?$"
                                    s))))
            (new-semtype NIL NIL
                         (if (svref match 6) (read-from-string (svref match 6)) 1)
                         (if (svref match 4) (read-from-string (svref match 4)) nil)
                         (if (svref match 3) (read-from-string (svref match 3)) nil)
                         :options (list (str2semtype (car (split-opt-str (svref match 0))))
                                        (str2semtype (cadr (split-opt-str (svref match 0)))))))
  
          ; ATOMIC
          (let ((match (nth-value 1 (cl-ppcre:scan-to-strings "^([A-Z]|[0-9])(_(([UT])|([NAVP])))?(\\^([A-Z]|[2-9]))?$" s))))
            (new-semtype (read-from-string (svref match 0)) NIL
                         (if (svref match 6) (read-from-string (svref match 6)) 1)
                         (if (svref match 4) (read-from-string (svref match 4)) nil)
                         (if (svref match 3) (read-from-string (svref match 3)) nil)))))))


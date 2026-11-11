;;; 명세 읽기 — XML 을 SXML(리스트)로 읽고, 스키마로 검사하면서 값을 풀어 둔다.
;;;
;;; SXML 은 XML 을 그대로 옮긴 리스트다:   <dot size="8" fill="live"/>   ⇒   (dot (@ (size "8") (fill "live")))
;;; 검사를 지나면 문자열이던 값이 뜻이 정해진 리스트가 된다:               ⇒   (dot (@ (size (num 8)) (fill (token live)) ...))
;;; 생성기(avalonia · android · html)는 검사를 지난 트리만 본다.
(defpackage :ui-gen (:use :cl))
(in-package :ui-gen)

;; ── 스키마 ── 요소마다: 자식 수, 속성 (이름 종류 [기본값]). 기본값이 없으면 꼭 적어야 한다
(defparameter *elements*
  '((row   :any (spacing number "0"))
    (box   :one-at-most (padding padding "0") (radius number "0") (fill color "#00000000"))
    (dot   :none (size number) (fill color))
    (label :none (text text) (size number) (color color) (bold flag "false"))))

;; 어느 요소에나 붙는 속성 — tap: 누르면 나는 event, visible: 보일지
(defparameter *common-attributes*
  '((tap event nil) (visible flag "true")))

;; ── 오류 ── 명세의 몇째 줄인지와 함께 알린다
(define-condition spec-error (error)
  ((line :initarg :line :reader spec-error-line)
   (message :initarg :message :reader spec-error-message)))

(defvar *lines* (make-hash-table :test 'eq) "읽은 요소 → XML 의 줄 번호")

(defun fail (node where fmt &rest args)
  (error 'spec-error
         :line (gethash node *lines*)
         :message (format nil "~a: ~?" where fmt args)))

;; ── XML → SXML ── .NET 의 System.Xml.Linq 로 읽어 리스트로 옮긴다
(defun name-symbol (string) (intern (string-upcase string) :ui-gen))

(defun enumerate (sequence)
  "IEnumerable → 리스트"
  (let ((e (dotnet:cast (dotnet:invoke (dotnet:cast sequence "System.Collections.IEnumerable") "GetEnumerator")
                        "System.Collections.IEnumerator"))
        (items '()))
    (loop while (dotnet:invoke e "MoveNext")
          do (push (dotnet:invoke e "Current") items))
    (nreverse items)))

(defun element->sxml (element)
  "(태그 (@ (속성 값) ...) 자식 ...)  — 속성이 없으면 @ 도 없다"
  (let* ((name (lambda (x) (name-symbol (dotnet:-> x "Name" "LocalName"))))
         (attrs (mapcar (lambda (a) (list (funcall name a) (dotnet:invoke a "Value")))
                        (enumerate (dotnet:invoke element "Attributes"))))
         (kids (mapcar #'element->sxml (enumerate (dotnet:invoke element "Elements"))))
         (node `(,(funcall name element) ,@(when attrs `((@ ,@attrs))) ,@kids)))
    (setf (gethash node *lines*)
          (dotnet:invoke (dotnet:cast element "System.Xml.IXmlLineInfo") "LineNumber"))
    node))

(defun read-xml (path)
  (clrhash *lines*)
  (element->sxml
   (dotnet:invoke (dotnet:static "System.Xml.Linq.XDocument" "Load" path
                                 (dotnet:static "System.Xml.Linq.LoadOptions" "SetLineInfo"))
                  "Root")))

;; ── SXML 다루기 ──
(defun tag (node) (first node))

(defun attributes (node)
  (let ((second (second node)))
    (if (and (consp second) (eq (first second) '@))
        (rest second)
        '())))

(defun children (node)
  (if (and (consp (second node)) (eq (first (second node)) '@))
      (cddr node)
      (cdr node)))

(defun attr (node name)
  "속성 값. 없으면 nil"
  (second (assoc name (attributes node))))

;; ── 값 풀기 ──
(defun parse-number (string)
  "\"8\" · \"0.5\" → 수. 아니면 nil"
  (when (and (plusp (length string))
             (every (lambda (c) (or (digit-char-p c) (char= c #\.))) string)
             (some #'digit-char-p string)
             (<= (count #\. string) 1))
    (let ((*read-eval* nil)) (read-from-string string))))

(defun parse-color (string)
  "\"#RRGGBB\" · \"#AARRGGBB\" → (color a r g b). 아니면 nil"
  (let* ((hex (subseq string 1))
         (n (ignore-errors (parse-integer hex :radix 16))))
    (flet ((octet (shift) (ldb (byte 8 shift) n)))
      (when n
        (case (length hex)
          (6 `(color 255 ,(octet 16) ,(octet 8) ,(octet 0)))
          (8 `(color ,(octet 24) ,(octet 16) ,(octet 8) ,(octet 0))))))))

(defun split-conditional (string)
  "\"조건 ? 값 : 값\" → (조건 값 값). 조건식이 아니면 nil"
  (let* ((q (search " ? " string))
         (c (and q (search " : " string :start2 q))))
    (when c
      (list (subseq string 0 q)
            (subseq string (+ q 3) c)
            (subseq string (+ c 3))))))

(defun starts-with (prefix string)
  (and (>= (length string) (length prefix))
       (string= prefix string :end2 (length prefix))))

(defun parse-word (word kind props colors node where)
  "낱말 하나 → (prop 이름) · (token 이름) · (color ..) · (num n) · (flag b) · (text \"..\").
props 는 ((이름 종류) ...), colors 는 (이름 ...)"
  (let* ((name (name-symbol word))
         (prop (assoc name props)))
    (cond
      (prop
       (if (eq (second prop) kind)
           `(prop ,name)
           (fail node where "~(~a~) 자리인데 ~a 은(는) ~(~a~) prop 이다" kind word (second prop))))
      ((and (eq kind 'color) (member name colors))
       `(token ,name))
      ((and (eq kind 'color) (starts-with "#" word) (parse-color word)))
      ((and (eq kind 'number) (parse-number word))
       `(num ,(parse-number word)))
      ((and (eq kind 'flag) (member word '("true" "false") :test #'string=))
       `(flag ,(string= word "true")))
      ((and (eq kind 'text) (> (length word) 1)
            (char= (char word 0) #\') (char= (char word (1- (length word))) #\'))
       `(text ,(subseq word 1 (1- (length word)))))
      (t
       (fail node where "\"~a\" 는 ~(~a~) 값이 아니다 — 선언한 이름도, 글자 그대로의 값도 아니다" word kind)))))

(defun split-words (string)
  (let ((words '()) (start nil))
    (loop for i from 0 to (length string)
          for space = (or (= i (length string)) (char= (char string i) #\Space))
          do (cond ((and space start) (push (subseq string start i) words) (setf start nil))
                   ((and (not space) (not start)) (setf start i))))
    (nreverse words)))

(defun parse-value (raw kind props colors events node where)
  "속성 문자열 → 뜻이 정해진 값"
  (case kind
    ;; "5" · "10 4"(가로 세로) · "14 6 8 6"(왼 위 오른 아래)
    (padding
     (let ((n (mapcar #'parse-number (split-words raw))))
       (unless (and n (every #'identity n) (member (length n) '(1 2 4)))
         (fail node where "\"~a\" 는 padding 값이 아니다 — 숫자 1 · 2 · 4개" raw))
       (destructuring-bind (a &optional (b a) (c a) (d b)) n
         `(padding ,a ,b ,c ,d))))
    (event
     (let ((name (name-symbol raw)))
       (if (member name events)
           name
           (fail node where "\"~a\" 는 선언한 event 가 아니다" raw))))
    (t
     (let ((conditional (split-conditional raw)))
       (if conditional
           (destructuring-bind (condition a b) conditional
             (let ((prop (assoc (name-symbol condition) props)))
               (unless (and prop (eq (second prop) 'flag))
                 (fail node where "조건 \"~a\" 는 flag prop 이어야 한다" condition))
               `(if ,(first prop)
                    ,(parse-word a kind props colors node where)
                    ,(parse-word b kind props colors node where))))
           (parse-word raw kind props colors node where))))))

;; ── 검사 ── 스키마에 맞는지 보면서, 속성을 스키마 순서대로 다 채운 트리를 만든다
(defun check-node (node props colors events path)
  (let* ((here (format nil "~a > ~(~a~)" path (tag node)))
         (rule (or (rest (assoc (tag node) *elements*))
                   (fail node here "모르는 요소")))
         (arity (first rule))
         (attr-rules (append (rest rule) *common-attributes*))
         (kids (children node)))
    (dolist (a (attributes node))
      (unless (assoc (first a) attr-rules)
        (fail node here "모르는 속성 ~(~a~)" (first a))))
    (unless (ecase arity
              (:any t)
              (:one-at-most (<= (length kids) 1))
              (:none (null kids)))
      (fail node here "자식이 ~a개다 — ~a" (length kids)
            (ecase arity (:one-at-most "하나까지만") (:none "둘 수 없다"))))
    `(,(tag node)
      (@ ,@(mapcar (lambda (attr-rule)
                     (destructuring-bind (name kind &optional (default nil default-given)) attr-rule
                       (let ((raw (or (attr node name)
                                      (if default-given
                                          default
                                          (fail node here "~(~a~) 속성이 없다" name)))))
                         (list name
                               (and raw (parse-value raw kind props colors events node
                                                     (format nil "~a 의 ~(~a~)" here name)))))))
                   attr-rules))
      ,@(mapcar (lambda (kid) (check-node kid props colors events here)) kids))))

(defun names-used (tree)
  "트리에서 쓰인 prop · event 이름"
  (cond
    ((atom tree) '())
    ((eq (first tree) 'prop) (list (second tree)))
    ((eq (first tree) 'if) (cons (second tree) (names-used (cddr tree))))
    ((and (eq (first tree) 'tap) (second tree) (symbolp (second tree))) (list (second tree)))
    (t (append (names-used (car tree)) (names-used (cdr tree))))))

(defun duplicate (names)
  (find-if (lambda (n) (> (count n names) 1)) names))

(defun check-example (node props colors where)
  "<example title=\"'작업'\" active=\"true\"/> → (example (title (text \"작업\")) (active (flag t)))"
  (dolist (a (attributes node))
    (unless (assoc (first a) props)
      (fail node where "example 의 ~(~a~) 은(는) 선언한 prop 이 아니다" (first a))))
  `(example
    ,@(mapcar (lambda (prop)
                (destructuring-bind (name kind) prop
                  (let ((raw (or (attr node name)
                                 (fail node where "example 에 ~(~a~) 값이 없다" name))))
                    ;; 보기의 값은 글자 그대로거나 색 이름 — prop 은 쓸 수 없다
                    (list name (parse-word raw kind '() colors node
                                           (format nil "~a 의 example ~(~a~)" where name))))))
              props)))

(defun check-component (node colors)
  (let* ((name (or (attr node 'name) (fail node "component" "name 속성이 없다")))
         (kids (children node))
         (props (loop for k in kids
                      when (eq (tag k) 'prop)
                        collect (let ((type (name-symbol (or (attr k 'type) ""))))
                                  (unless (member type '(text color flag))
                                    (fail k name "prop ~a 의 type 은 text · color · flag 중 하나" (attr k 'name)))
                                  (list (name-symbol (attr k 'name)) type))))
         (events (loop for k in kids when (eq (tag k) 'event) collect (name-symbol (attr k 'name))))
         (examples (loop for k in kids when (eq (tag k) 'example) collect (check-example k props colors name)))
         (roots (remove-if (lambda (k) (member (tag k) '(prop event example))) kids))
         (backdrop (attr node 'backdrop)))
    (unless (= (length roots) 1)
      (fail node name "뿌리 요소는 하나여야 하는데 ~a개다" (length roots)))
    (let* ((root (check-node (first roots) props colors events name))
           (declared (append (mapcar #'first props) events))
           (used (names-used root))
           (unused (remove-if (lambda (n) (member n used)) declared)))
      (when (duplicate declared)
        (fail node name "~(~a~) 을(를) 두 번 선언했다" (duplicate declared)))
      (when unused
        (fail node name "~(~a~) 을(를) 선언만 하고 쓰지 않았다" (first unused)))
      `(component (@ (name ,(name-symbol name))
                     (doc ,(or (attr node 'doc) ""))
                     ;; 보기를 놓을 바탕색
                     (backdrop ,(parse-word (or backdrop "#00000000") 'color '() colors node
                                            (format nil "~a 의 backdrop" name))))
                  (props ,@props)
                  (events ,@events)
                  (examples ,@examples)
                  ,root))))

(defun check-spec (ui)
  "(ui ...) → (ui (colors (이름 a r g b) ...) (component ...) ...)"
  (unless (eq (tag ui) 'ui)
    (fail ui "뿌리" "ui 여야 하는데 ~(~a~) 다" (tag ui)))
  (dolist (k (children ui))
    (unless (member (tag k) '(color component))
      (fail k "ui" "color · component 만 올 수 있다: ~(~a~)" (tag k))))
  (let* ((colors (loop for c in (children ui)
                       when (eq (tag c) 'color)
                         collect (let ((value (attr c 'value)))
                                   (cons (name-symbol (attr c 'name))
                                         (rest (or (and (starts-with "#" value) (parse-color value))
                                                   (fail c (attr c 'name) "\"~a\" 는 색이 아니다" value)))))))
         (components (loop for c in (children ui)
                           when (eq (tag c) 'component)
                             collect (check-component c (mapcar #'first colors)))))
    (when (duplicate (mapcar #'first colors))
      (fail ui "ui" "color ~(~a~) 을(를) 두 번 선언했다" (duplicate (mapcar #'first colors))))
    (when (duplicate (mapcar #'component-name components))
      (fail ui "ui" "component ~(~a~) 을(를) 두 번 선언했다" (duplicate (mapcar #'component-name components))))
    `(ui (colors ,@colors) ,@components)))

;; ── 플랫폼과 무관한 뜻 ──
(defun line-height (label)
  "label 한 줄의 높이 — 글꼴마다 다른 줄 높이에 맡기지 않고 글자 크기의 1.4배로 정한다"
  (round (* 1.4 (second (attr label 'size)))))

;; ── 검사를 지난 트리 꺼내 쓰기 ──
(defun spec-colors (spec) (rest (assoc 'colors (rest spec))))
(defun spec-components (spec) (remove 'component (rest spec) :key #'first :test-not #'eq))
(defun component-name (c) (attr c 'name))
(defun component-doc (c) (attr c 'doc))
(defun component-backdrop (c) (attr c 'backdrop))
(defun component-props (c) (rest (assoc 'props (children c))))
(defun component-events (c) (rest (assoc 'events (children c))))
(defun component-examples (c) (rest (assoc 'examples (children c))))
(defun component-root (c) (first (last c)))

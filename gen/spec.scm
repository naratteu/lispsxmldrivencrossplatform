;;; 명세 읽기 — XML 을 SXML(리스트)로 읽고, 스키마로 검사하면서 값을 풀어 둔다.
;;;
;;; SXML 은 XML 을 그대로 옮긴 리스트다:   <dot size="8" fill="live"/>   ⇒   (dot (@ (size "8") (fill "live")))
;;; 검사를 지나면 문자열이던 값이 뜻이 정해진 리스트가 된다:               ⇒   (dot (@ (size (num 8)) (fill (token live)) ...))
;;; 생성기(avalonia.scm · android.scm)는 검사를 지난 트리만 본다.
(define-module (spec)
  #:use-module (sxml simple)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:export (read-xml check-spec
            tag attr children
            spec-colors spec-components
            component-name component-doc component-props component-events component-root))

;; ── 스키마 ── 요소마다: 자식 수, 속성 (이름 종류 [기본값]). 기본값이 없으면 꼭 적어야 한다
(define elements
  '((row   any  (spacing number "0"))
    (box   0-1  (padding padding "0") (radius number "0") (fill color "#00000000"))
    (dot   0    (size number) (fill color))
    (label 0    (text text) (size number) (color color) (bold flag "false"))))

;; 어느 요소에나 붙는 속성 — tap: 누르면 나는 event, visible: 보일지
(define common-attributes
  '((tap event #f) (visible flag "true")))

;; ── SXML 다루기 ── (태그 (@ (속성 값) ...) 자식 ...)  — @ 는 없을 수도 있다
(define (tag node) (car node))

(define (attributes node)
  (match node
    ((_ ('@ . attrs) . _) attrs)
    (_ '())))

(define (children node)
  (match node
    ((_ ('@ . _) . kids) kids)
    ((_ . kids) kids)))

;; 속성 값. 없으면 #f
(define (attr node name)
  (let ((found (assq name (attributes node))))
    (and found (cadr found))))

;; XML 파일 → SXML 의 뿌리 요소
(define (read-xml path)
  (let ((top (call-with-input-file path
               (lambda (port) (xml->sxml port #:trim-whitespace? #t))
               #:encoding "UTF-8")))
    ;; (*TOP* (*PI* xml ...) (ui ...)) 에서 (ui ...) 만
    (find (lambda (x) (and (pair? x) (not (eq? (car x) '*PI*))))
          (cdr top))))

;; ── 값 풀기 ──
(define (fail where fmt . args)
  (throw 'spec-error (string-append where ": " (apply format #f fmt args))))

;; "#RRGGBB" · "#AARRGGBB" → (color a r g b). 아니면 #f
(define (parse-color s)
  (let* ((hex (substring s 1))
         (n (string->number hex 16))
         (byte (lambda (shift) (logand (ash n (- shift)) 255))))
    (and n
         (case (string-length hex)
           ((6) `(color 255 ,(byte 16) ,(byte 8) ,(byte 0)))
           ((8) `(color ,(byte 24) ,(byte 16) ,(byte 8) ,(byte 0)))
           (else #f)))))

;; "조건 ? 값 : 값" → (조건 값 값). 조건식이 아니면 #f
(define (split-conditional s)
  (let* ((q (string-contains s " ? "))
         (c (and q (string-contains s " : " q))))
    (and c (list (substring s 0 q)
                 (substring s (+ q 3) c)
                 (substring s (+ c 3))))))

;; 낱말 하나 → (prop 이름) · (token 이름) · (color ..) · (num n) · (flag b) · (text "..")
;; props 는 ((이름 종류) ...), colors 는 (이름 ...)
(define (parse-word word kind props colors where)
  (let* ((name (string->symbol word))
         (prop (assq name props)))
    (cond
     (prop
      (if (eq? (cadr prop) kind)
          `(prop ,name)
          (fail where "~a 자리인데 ~a 은(는) ~a prop 이다" kind word (cadr prop))))
     ((and (eq? kind 'color) (memq name colors))
      `(token ,name))
     ((and (eq? kind 'color) (string-prefix? "#" word) (parse-color word)))
     ((and (eq? kind 'number) (string->number word))
      `(num ,(string->number word)))
     ((and (eq? kind 'flag) (member word '("true" "false")))
      `(flag ,(string=? word "true")))
     ((and (eq? kind 'text) (> (string-length word) 1)
           (string-prefix? "'" word) (string-suffix? "'" word))
      `(text ,(substring word 1 (- (string-length word) 1))))
     (else
      (fail where "\"~a\" 는 ~a 값이 아니다 — 선언한 이름도, 글자 그대로의 값도 아니다" word kind)))))

;; 속성 문자열 → 뜻이 정해진 값
(define (parse-value raw kind props colors events where)
  (case kind
    ;; "5" · "10 4"(가로 세로) · "14 6 8 6"(왼 위 오른 아래)
    ((padding)
     (match (map string->number (string-tokenize raw))
       (((? number? a)) `(padding ,a ,a ,a ,a))
       (((? number? h) (? number? v)) `(padding ,h ,v ,h ,v))
       (((? number? l) (? number? t) (? number? r) (? number? b)) `(padding ,l ,t ,r ,b))
       (_ (fail where "\"~a\" 는 padding 값이 아니다 — 숫자 1 · 2 · 4개" raw))))
    ((event)
     (let ((name (string->symbol raw)))
       (if (memq name events) name (fail where "\"~a\" 는 선언한 event 가 아니다" raw))))
    (else
     (match (split-conditional raw)
       ((condition a b)
        (let ((prop (assq (string->symbol condition) props)))
          (unless (and prop (eq? (cadr prop) 'flag))
            (fail where "조건 \"~a\" 는 flag prop 이어야 한다" condition))
          `(if ,(car prop)
               ,(parse-word a kind props colors where)
               ,(parse-word b kind props colors where))))
       (#f (parse-word raw kind props colors where))))))

;; ── 검사 ── 스키마에 맞는지 보면서, 속성을 스키마 순서대로 다 채운 트리를 만든다
(define (check-node node props colors events path)
  (unless (pair? node)
    (fail path "요소 밖의 글자 \"~a\"" node))
  (let* ((here (string-append path " > " (symbol->string (tag node))))
         (rule (or (assq-ref elements (tag node))
                   (fail here "모르는 요소")))
         (arity (car rule))
         (attr-rules (append (cdr rule) common-attributes))
         (kids (children node)))
    (for-each (lambda (a)
                (unless (assq (car a) attr-rules)
                  (fail here "모르는 속성 ~a" (car a))))
              (attributes node))
    (unless (case arity
              ((any) #t)
              ((0-1) (<= (length kids) 1))
              (else (= (length kids) arity)))
      (fail here "자식은 ~a개여야 하는데 ~a개다" arity (length kids)))
    `(,(tag node)
      (@ ,@(map (match-lambda
                  ((name kind . default)
                   (let ((raw (or (attr node name)
                                  (if (null? default)
                                      (fail here "~a 속성이 없다" name)
                                      (car default))))
                         (where (format #f "~a 의 ~a" here name)))
                     (list name (and raw (parse-value raw kind props colors events where))))))
                attr-rules))
      ,@(map (lambda (kid) (check-node kid props colors events here)) kids))))

;; 트리에서 쓰인 prop · event 이름
(define (names-used tree)
  (match tree
    (('prop name) (list name))
    (('if name a b) (cons name (append (names-used a) (names-used b))))
    (('tap (? symbol? name)) (list name))
    ((x . rest) (append (names-used x) (names-used rest)))
    (_ '())))

(define (duplicate names)
  (find (lambda (n) (> (count (lambda (m) (eq? m n)) names) 1)) names))

(define (check-component node colors)
  (let* ((name (or (attr node 'name) (fail "component" "name 속성이 없다")))
         (kids (children node))
         (of (lambda (t) (filter (lambda (k) (and (pair? k) (eq? (tag k) t))) kids)))
         (props (map (lambda (p)
                       (let ((type (string->symbol (or (attr p 'type) ""))))
                         (unless (memq type '(text color flag))
                           (fail name "prop ~a 의 type 은 text · color · flag 중 하나" (attr p 'name)))
                         (list (string->symbol (attr p 'name)) type)))
                     (of 'prop)))
         (events (map (lambda (e) (string->symbol (attr e 'name))) (of 'event)))
         (roots (remove (lambda (k) (and (pair? k) (memq (tag k) '(prop event)))) kids)))
    (unless (= (length roots) 1)
      (fail name "뿌리 요소는 하나여야 하는데 ~a개다" (length roots)))
    (let* ((root (check-node (car roots) props colors events name))
           (declared (append (map car props) events))
           (used (names-used root))
           (unused (remove (lambda (n) (memq n used)) declared)))
      (when (duplicate declared)
        (fail name "~a 을(를) 두 번 선언했다" (duplicate declared)))
      (unless (null? unused)
        (fail name "~a 을(를) 선언만 하고 쓰지 않았다" (car unused)))
      `(component (@ (name ,(string->symbol name)) (doc ,(or (attr node 'doc) "")))
                  (props ,@props)
                  (events ,@events)
                  ,root))))

;; (ui ...) → (ui (colors (이름 a r g b) ...) (component ...) ...)
(define (check-spec ui)
  (unless (eq? (tag ui) 'ui)
    (fail "뿌리" "ui 여야 하는데 ~a 다" (tag ui)))
  (for-each (lambda (k)
              (unless (and (pair? k) (memq (tag k) '(color component)))
                (fail "ui" "color · component 만 올 수 있다: ~a" (if (pair? k) (tag k) k))))
            (children ui))
  (let* ((of (lambda (t) (filter (lambda (k) (eq? (tag k) t)) (children ui))))
         (colors (map (lambda (c)
                        (let ((value (attr c 'value)))
                          (cons (string->symbol (attr c 'name))
                                (cdr (or (and (string-prefix? "#" value) (parse-color value))
                                         (fail (attr c 'name) "\"~a\" 는 색이 아니다" value))))))
                      (of 'color)))
         (components (map (lambda (c) (check-component c (map car colors))) (of 'component))))
    (when (duplicate (map car colors))
      (fail "ui" "color ~a 을(를) 두 번 선언했다" (duplicate (map car colors))))
    (when (duplicate (map component-name components))
      (fail "ui" "component ~a 을(를) 두 번 선언했다" (duplicate (map component-name components))))
    `(ui (colors ,@colors) ,@components)))

;; ── 검사를 지난 트리 꺼내 쓰기 ──
(define (spec-colors spec) (cdr (assq 'colors (cdr spec))))
(define (spec-components spec) (filter (lambda (x) (eq? (tag x) 'component)) (cdr spec)))
(define (component-name c) (attr c 'name))
(define (component-doc c) (attr c 'doc))
(define (component-props c) (cdr (assq 'props (children c))))
(define (component-events c) (cdr (assq 'events (children c))))
(define (component-root c) (last c))

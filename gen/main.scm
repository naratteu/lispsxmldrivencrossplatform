;;; 생성기 입구.
;;;   guile -L gen gen/main.scm ui.xml sxml                  읽은 그대로의 SXML
;;;   guile -L gen gen/main.scm ui.xml checked               검사 · 값 풀기를 지난 트리
;;;   guile -L gen gen/main.scm ui.xml avalonia [출력.cs]     Avalonia 컨트롤(C#)
;;;   guile -L gen gen/main.scm ui.xml android  [출력.cs]     Android 뷰(C#)
(use-modules (spec) (avalonia) (android)
             (ice-9 match) (ice-9 pretty-print))

;; thunk 가 찍는 것을 파일로. 임시 파일에 쓰고 바꿔치기한다 — 여러 빌드가 동시에 써도 깨진 파일이 보이지 않게
(define (print-to path thunk)
  (let ((temp (format #f "~a.~a.tmp" path (getpid))))
    (with-output-to-file temp thunk #:encoding "UTF-8")
    (rename-file temp path)))

(define (generate spec-path target out)
  (let* ((xml (read-xml spec-path))
         (print (match target
                  ("sxml" (lambda () (pretty-print xml)))
                  ("checked" (lambda () (pretty-print (check-spec xml))))
                  ("avalonia" (lambda () (print-avalonia (check-spec xml))))
                  ("android" (lambda () (print-android (check-spec xml)))))))
    (match out
      (() (print))
      ((path) (print-to path print)))))

;; MSBuild 가 오류로 알아보는 꼴로 알리고 끝낸다: 파일 : error 코드: 내용
(define (stop spec-path message)
  (format (current-error-port) "~a : error UI0001: ~a\n" spec-path message)
  (exit 1))

(define (main args)
  (match args
    ((_ spec-path target . out)
     (catch 'parser-error   ; XML 자체가 깨졌을 때
       (lambda ()
         (catch 'spec-error   ; 명세가 스키마에 안 맞을 때
           (lambda () (generate spec-path target out))
           (lambda (key message) (stop spec-path message))))
       (lambda (key port . details)
         (stop spec-path
               (string-append "XML 을 읽을 수 없다 —"
                              (string-concatenate (map (lambda (d) (format #f " ~a" d)) details)))))))
    (else
     (format (current-error-port) "guile -L gen gen/main.scm <명세.xml> <sxml|checked|avalonia|android> [출력]\n")
     (exit 2))))

(main (command-line))

;;; 생성기 입구.  dotnet dotcl gen/main.lisp <명세.xml> <대상> [출력]
;;;   sxml       읽은 그대로의 SXML
;;;   checked    검사 · 값 풀기를 지난 트리
;;;   avalonia   Avalonia 컨트롤(C#)
;;;   android    Android 뷰(C#)
;;;   html       플랫폼 중립 프리뷰(HTML)
;;;   serve      프리뷰 서버 — 명세나 생성기를 저장하면 브라우저가 바로 바뀐다. [출력] 자리에 포트(기본 8090)
(defparameter cl-user::*here* *load-truename*)
(defparameter cl-user::*files* '("spec" "csharp" "avalonia" "android" "html"))

(defun cl-user::generator-file (name)
  (merge-pathnames (concatenate 'string name ".lisp") cl-user::*here*))

(defun cl-user::load-generator ()
  (mapc (lambda (name) (load (cl-user::generator-file name))) cl-user::*files*))

(cl-user::load-generator)
(in-package :ui-gen)

(defun generate (spec-path target)
  (let ((xml (read-xml spec-path))
        (*print-case* :downcase)
        (*print-right-margin* 100))
    (cond
      ((string= target "sxml") (pprint xml) (terpri))
      ((string= target "checked") (pprint (check-spec xml)) (terpri))
      ((string= target "avalonia") (print-avalonia (check-spec xml)))
      ((string= target "android") (print-android (check-spec xml)))
      ((string= target "html") (print-html (check-spec xml)))
      ((string= target "live") (print-html (check-spec xml) :live t))
      (t (error "모르는 대상 ~a" target)))))

;; ── 프리뷰 서버 ──
(defun modified (path)
  (dotnet:invoke (dotnet:static "System.IO.File" "GetLastWriteTimeUtc" (namestring path)) "Ticks"))

(defun generator-version ()
  (reduce #'max (mapcar (lambda (name) (modified (cl-user::generator-file name))) cl-user::*files*)))

(defun error-page (line message)
  (format nil "<!doctype html><meta charset=\"utf-8\"><pre style=\"margin:24px;font-size:14px;color:#b91c1c;white-space:pre-wrap\">~@[~a 째 줄 — ~]~a</pre>
<script>let seen = null; setInterval(async () => { const v = await (await fetch('/version')).text(); if (seen !== null && v !== seen) location.reload(); seen = v; }, 300);</script>"
          line (html-escape (format nil "~a" message))))

(defun serve (spec-path port)
  (let ((listener (dotnet:new "System.Net.HttpListener"))
        (loaded (generator-version)))
    (dotnet:invoke (dotnet:invoke listener "Prefixes") "Add" (format nil "http://localhost:~a/" port))
    (dotnet:invoke listener "Start")
    (format t "프리뷰: http://localhost:~a/   (끝내려면 Ctrl+C)~%" port)
    (loop
      (let* ((context (dotnet:invoke listener "GetContext"))
             (response (dotnet:invoke context "Response"))
             (version? (string= (dotnet:-> context "Request" "Url" "AbsolutePath") "/version"))
             (body
               (if version?
                   (format nil "~a ~a" (modified spec-path) (generator-version))
                   (handler-case
                       (progn
                         ;; 생성기 파일이 바뀌었으면 다시 읽는다 — 서버를 끄지 않고 생성기를 고칠 수 있다
                         (when (/= loaded (generator-version))
                           (cl-user::load-generator)
                           (setf loaded (generator-version)))
                         (with-output-to-string (*standard-output*)
                           (generate spec-path "live")))
                     (spec-error (e) (error-page (spec-error-line e) (spec-error-message e)))
                     (error (e) (error-page nil e)))))
             (bytes (dotnet:invoke (dotnet:static "System.Text.Encoding" "UTF8") "GetBytes" body)))
        (setf (dotnet:invoke response "ContentType")
              (if version? "text/plain" "text/html; charset=utf-8"))
        (dotnet:invoke (dotnet:invoke response "OutputStream") "Write" bytes 0 (dotnet:invoke bytes "Length"))
        (dotnet:invoke response "Close")))))

;; ── 명령줄 ──
(defun report (spec-path line message)
  "컴파일러 오류와 같은 꼴로 알린다: 파일(줄) : error 코드: 내용"
  (format *error-output* "~a~@[(~a)~] : error UI0001: ~a~%" spec-path line message))

(defun main (arguments)
  (destructuring-bind (&optional spec-path target out) arguments
    (unless target
      (format *error-output* "dotnet dotcl gen/main.lisp <명세.xml> <sxml|checked|avalonia|android|html|serve> [출력]~%")
      (dotcl:quit 2))
    (handler-case
        (cond
          ((string= target "serve")
           (serve spec-path (if out (parse-integer out) 8090)))
          (out
           (with-open-file (*standard-output* out :direction :output :if-exists :supersede
                                                  :external-format :utf-8)
             (generate spec-path target)))
          (t (generate spec-path target)))
      (spec-error (e)   ; 명세가 스키마에 안 맞을 때
        (report spec-path (spec-error-line e) (spec-error-message e))
        (dotcl:quit 1))
      (error (e)        ; XML 자체가 깨졌을 때 등
        (report spec-path nil e)
        (dotcl:quit 1)))))

(main (dotcl:script-arguments))

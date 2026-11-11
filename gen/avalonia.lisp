;;; Avalonia 컨트롤 생성 — 요소 하나가 객체 초기화 식 하나가 된다(식 안에 식이 들어가는 꼴)
(in-package :ui-gen)

(defun avalonia-value (v) (cs-value v "Color.FromArgb"))
(defun avalonia-brush (v) (format nil "new SolidColorBrush(~a)" (avalonia-value v)))
(defun indent (depth) (make-string (* 4 depth) :initial-element #\Space))

(defun avalonia-expression (node depth)
  "요소 → C# 식(문자열). depth 는 들여쓰기 깊이"
  (flet ((a (name) (attr node name)))
    (let* ((pad (indent depth))
           (inner (indent (+ depth 1)))
           (kids (mapcar (lambda (kid) (avalonia-expression kid (+ depth 2))) (children node)))
           ;; 요소마다: 컨트롤 종류, 속성 대입들
           (type+props
             (ecase (tag node)
               (row
                (list "StackPanel"
                      "Orientation = Orientation.Horizontal"
                      (format nil "Spacing = ~a" (avalonia-value (a 'spacing)))))
               (box
                (list "Border"
                      (format nil "Padding = new Thickness(~{~a~^, ~})" (rest (a 'padding)))
                      (format nil "CornerRadius = new CornerRadius(~a)" (avalonia-value (a 'radius)))
                      (format nil "Background = ~a" (avalonia-brush (a 'fill)))))
               (dot
                (list "Ellipse"
                      (format nil "Width = ~a" (avalonia-value (a 'size)))
                      (format nil "Height = ~a" (avalonia-value (a 'size)))
                      (format nil "Fill = ~a" (avalonia-brush (a 'fill)))))
               (label
                (list "TextBlock"
                      (format nil "Text = ~a" (avalonia-value (a 'text)))
                      (format nil "FontSize = ~a" (avalonia-value (a 'size)))
                      (format nil "LineHeight = ~a" (line-height node))
                      (format nil "FontWeight = ~a"
                              (cs-choice (a 'bold) "FontWeight.Bold" "FontWeight.Normal" "Color.FromArgb"))
                      (format nil "Foreground = ~a" (avalonia-brush (a 'color)))
                      ;; 글자 사이 빈 곳도 눌리게
                      (when (a 'tap) "Background = Brushes.Transparent")))))
           (props (remove nil
                          (append (rest type+props)
                                  (list "VerticalAlignment = VerticalAlignment.Center"
                                        (unless (equal (a 'visible) '(flag t))
                                          (format nil "IsVisible = ~a" (avalonia-value (a 'visible))))))))
           (body (join props (format nil ",~%~a" inner)))
           ;; 자식: row 는 Children 에 여럿, box 는 Child 하나
           (kids-part
             (cond
               ((null kids) "")
               ((eq (tag node) 'row)
                (format nil ",~%~aChildren =~%~a{~%~{~a~a,~%~}~a}"
                        inner inner
                        (loop for k in kids append (list (indent (+ depth 2)) k))
                        inner))
               (t
                (format nil ",~%~aChild =~%~a~a" inner (indent (+ depth 2)) (first kids)))))
           (object (format nil "new ~a~%~a{~%~a~a~a~%~a}" (first type+props) pad inner body kids-part pad)))
      (if (a 'tap)
          (format nil "Tap(~a, () => ~a())" object (pascal (a 'tap)))
          object))))

(defun print-avalonia-component (component)
  (line "")
  (line "/// ~a" (component-doc component))
  (line "public sealed class ~a : Decorator" (pascal (component-name component)))
  (line "{")
  (print-members component)
  (line "")
  (line "    public ~a() => Render();" (pascal (component-name component)))
  (line "")
  (line "    void Render() => Child =")
  (line "        ~a;" (avalonia-expression (component-root component) 2))
  (line "")
  (line "    static T Tap<T>(T control, Action action) where T : Control")
  (line "    {")
  (line "        control.Cursor = new Cursor(StandardCursorType.Hand);")
  (line "        control.PointerReleased += (_, e) => { e.Handled = true; action(); };")
  (line "        return control;")
  (line "    }")
  (line "}"))

(defun print-avalonia (spec)
  (print-header '("Avalonia" "Avalonia.Controls" "Avalonia.Controls.Shapes"
                  "Avalonia.Input" "Avalonia.Layout" "Avalonia.Media"))
  (print-tokens spec "Color.FromArgb")
  (mapc #'print-avalonia-component (spec-components spec))
  (print-examples spec "Color.FromArgb" "Control" ""
                 (lambda (type) (format nil "new ~a" type))))

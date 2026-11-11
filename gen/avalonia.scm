;;; Avalonia 컨트롤 생성 — 요소 하나가 객체 초기화 식 하나가 된다(식 안에 식이 들어가는 꼴)
(define-module (avalonia)
  #:use-module (spec)
  #:use-module (csharp)
  #:use-module (ice-9 match)
  #:export (print-avalonia))

(define (value v) (cs-value v "Color.FromArgb"))
(define (brush v) (format #f "new SolidColorBrush(~a)" (value v)))
(define (indent depth) (make-string (* 4 depth) #\space))

;; 요소 → C# 식(문자열). depth 는 들여쓰기 깊이
(define (expression node depth)
  (let* ((a (lambda (name) (attr node name)))
         (pad (indent depth))
         (inner (indent (+ depth 1)))
         (kids (map (lambda (kid) (expression kid (+ depth 2))) (children node)))
         ;; 요소마다: 컨트롤 종류, 속성 대입들
         (type+props
          (case (tag node)
            ((row)
             (list "StackPanel"
                   "Orientation = Orientation.Horizontal"
                   (format #f "Spacing = ~a" (value (a 'spacing)))))
            ((box)
             (list "Border"
                   (match (a 'padding)
                     (('padding l t r b) (format #f "Padding = new Thickness(~a, ~a, ~a, ~a)" l t r b)))
                   (format #f "CornerRadius = new CornerRadius(~a)" (value (a 'radius)))
                   (format #f "Background = ~a" (brush (a 'fill)))))
            ((dot)
             (list "Ellipse"
                   (format #f "Width = ~a" (value (a 'size)))
                   (format #f "Height = ~a" (value (a 'size)))
                   (format #f "Fill = ~a" (brush (a 'fill)))))
            ((label)
             (list "TextBlock"
                   (format #f "Text = ~a" (value (a 'text)))
                   (format #f "FontSize = ~a" (value (a 'size)))
                   (format #f "FontWeight = ~a" (cs-choice (a 'bold) "FontWeight.Bold" "FontWeight.Normal" "Color.FromArgb"))
                   (format #f "Foreground = ~a" (brush (a 'color)))
                   ;; 글자 사이 빈 곳도 눌리게
                   (if (a 'tap) "Background = Brushes.Transparent" #f)))))
         (props (filter identity
                        (append (cdr type+props)
                                (list "VerticalAlignment = VerticalAlignment.Center"
                                      (if (equal? (a 'visible) '(flag #t))
                                          #f
                                          (format #f "IsVisible = ~a" (value (a 'visible))))))))
         (body (string-join props (string-append ",\n" inner)))
         ;; 자식: row 는 Children 에 여럿, box 는 Child 하나
         (kids-part
          (cond
           ((null? kids) "")
           ((eq? (tag node) 'row)
            (format #f ",\n~aChildren =\n~a{\n~a\n~a}"
                    inner inner
                    (string-join (map (lambda (k) (string-append (indent (+ depth 2)) k ",")) kids) "\n")
                    inner))
           (else
            (format #f ",\n~aChild =\n~a~a" inner (indent (+ depth 2)) (car kids)))))
         (object (format #f "new ~a\n~a{\n~a~a~a\n~a}" (car type+props) pad inner body kids-part pad)))
    (if (a 'tap)
        (format #f "Tap(~a, () => ~a())" object (pascal (a 'tap)))
        object)))

(define (print-component component)
  (line "")
  (line "/// ~a" (component-doc component))
  (line "public sealed class ~a : Decorator" (pascal (component-name component)))
  (line "{")
  (print-members component)
  (line "")
  (line "    public ~a() => Render();" (pascal (component-name component)))
  (line "")
  (line "    void Render() => Child =")
  (line "        ~a;" (expression (component-root component) 2))
  (line "")
  (line "    static T Tap<T>(T control, Action action) where T : Control")
  (line "    {")
  (line "        control.Cursor = new Cursor(StandardCursorType.Hand);")
  (line "        control.PointerReleased += (_, e) => { e.Handled = true; action(); };")
  (line "        return control;")
  (line "    }")
  (line "}"))

(define (print-avalonia spec)
  (print-header '("Avalonia" "Avalonia.Controls" "Avalonia.Controls.Shapes"
                  "Avalonia.Input" "Avalonia.Layout" "Avalonia.Media"))
  (print-tokens spec "Color.FromArgb")
  (for-each print-component (spec-components spec)))

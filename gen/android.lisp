;;; Android 뷰 생성 — 요소 하나가 문장 여러 줄이 된다(뷰를 만들고, 설정하고, 부모에 붙인다)
(in-package :ui-gen)

(defun android-value (v) (cs-value v "Color.Argb"))
(defun px (v) (format nil "Px(~a)" (if (numberp v) v (android-value v))))

(defun android-size (node)
  "부모가 자식에게 줄 크기 — dot 만 정해진 크기, 나머지는 내용만큼"
  (if (eq (tag node) 'dot)
      (format nil "~a, ~a" (px (attr node 'size)) (px (attr node 'size)))
      "Wrap, Wrap"))

(defun android-statements (node fresh)
  "요소의 문장들을 찍고, 그 뷰를 담은 변수 이름을 돌려준다. fresh 는 새 변수 이름을 주는 함수"
  (flet ((a (name) (attr node name)))
    (let ((v (funcall fresh)))
      (ecase (tag node)
        (row
         (line "        var ~a = new LinearLayout(context) { Orientation = Orientation.Horizontal };" v)
         (line "        ~a.SetGravity(GravityFlags.CenterVertical);" v)
         (loop for child in (children node)
               for first = t then nil
               do (let ((kid (android-statements child fresh)))
                    (line "        ~a.AddView(~a, new LinearLayout.LayoutParams(~a)~a);"
                          v kid (android-size child)
                          ;; 둘째부터 간격만큼 띄운다
                          (if first "" (format nil " { LeftMargin = ~a }" (px (a 'spacing))))))))
        (box
         (line "        var ~a = new FrameLayout(context);" v)
         (line "        ~a.SetPadding(~{~a~^, ~});" v (mapcar #'px (rest (a 'padding))))
         (line "        ~a.Background = Fill(~a, ~a, oval: false);" v (android-value (a 'fill)) (px (a 'radius)))
         (dolist (child (children node))
           (let ((kid (android-statements child fresh)))
             (line "        ~a.AddView(~a, new FrameLayout.LayoutParams(~a) { Gravity = GravityFlags.Center });"
                   v kid (android-size child)))))
        (dot
         (line "        var ~a = new View(context) { Background = Fill(~a, 0, oval: true) };" v (android-value (a 'fill))))
        (label
         (line "        var ~a = new TextView(context) { Text = ~a };" v (android-value (a 'text)))
         (line "        ~a.SetTextSize(ComplexUnitType.Dip, ~a);" v (android-value (a 'size)))
         (line "        ~a.SetTextColor(~a);" v (android-value (a 'color)))
         (line "        ~a.SetTypeface(null, ~a);" v
               (cs-choice (a 'bold) "TypefaceStyle.Bold" "TypefaceStyle.Normal" "Color.Argb"))
         (line "        ~a.SetIncludeFontPadding(false);" v)
         ;; 줄 높이를 정해 두고 그 안에서 세로 가운데
         (line "        ~a.SetHeight(~a);" v (px (line-height node)))
         (line "        ~a.Gravity = GravityFlags.CenterVertical;" v)))
      (unless (equal (a 'visible) '(flag t))
        (line "        ~a.Visibility = ~a ? ViewStates.Visible : ViewStates.Gone;" v (android-value (a 'visible))))
      (when (a 'tap)
        (line "        ~a.Click += (_, _) => ~a();" v (pascal (a 'tap))))
      v)))

(defun print-android-component (component)
  (let* ((name (pascal (component-name component)))
         (root (component-root component))
         ;; v1, v2, ... 를 차례로 주는 함수
         (count 0)
         (fresh (lambda () (format nil "v~a" (incf count)))))
    (line "")
    (line "/// ~a" (component-doc component))
    (line "public sealed class ~a : FrameLayout" name)
    (line "{")
    (print-members component)
    (line "")
    (line "    public ~a(Context context) : base(context) => Render();" name)
    (line "")
    (line "    void Render()")
    (line "    {")
    (line "        var context = Context!;")
    (line "        RemoveAllViews();")
    (let ((v (android-statements root fresh)))
      (line "        AddView(~a, new LayoutParams(~a) { Gravity = GravityFlags.Center });" v (android-size root)))
    (line "    }")
    (line "")
    (line "    const int Wrap = ViewGroup.LayoutParams.WrapContent;")
    (line "    int Px(double dp) => (int)Math.Round(dp * Resources!.DisplayMetrics!.Density);")
    (line "    static GradientDrawable Fill(Color color, int radius, bool oval)")
    (line "    {")
    (line "        var fill = new GradientDrawable();")
    (line "        if (oval) fill.SetShape(ShapeType.Oval); else fill.SetCornerRadius(radius);")
    (line "        fill.SetColor(color);")
    (line "        return fill;")
    (line "    }")
    (line "}")))

(defun print-android (spec)
  (print-header '("Android.Content" "Android.Graphics" "Android.Graphics.Drawables"
                  "Android.Util" "Android.Views" "Android.Widget"))
  (print-tokens spec "Color.Argb")
  (mapc #'print-android-component (spec-components spec))
  (print-examples spec "Color.Argb" "View" "Context context"
                 (lambda (type) (format nil "new ~a(context)" type))))

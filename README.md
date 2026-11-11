# lispsxmldrivencrossplatform

UI 를 자체 스키마의 XML 로 적고, Lisp(Scheme)가 그것을 SXML 로 읽어 플랫폼별 네이티브 UI 코드를 생성하는 PoC.
[fsharpdsldrivencrossplatform](https://github.com/naratteu/fsharpdsldrivencrossplatform) 의 후속 — 명세를 F# 코드에서 XML 로 옮기고, 생성기를 Lisp 로 바꿨다.

같은 `ui.xml` 에서 서로 호환되지 않는 두 UI 프레임워크의 코드가 나온다.

- **Avalonia** 컨트롤(C#) — 데스크톱
- **Android** 뷰(C#) — .NET Android

## 흐름

```
ui.xml ──읽기──▶ SXML ──검사 · 값 풀기──▶ 검사를 지난 트리 ──┬─▶ avalonia.scm ─▶ obj/gen/Ui.g.cs (Avalonia)
 사람이 읽고 쓴다   리스트    스키마에 안 맞으면 여기서 오류          └─▶ android.scm  ─▶ obj/gen/Ui.g.cs (Android)
```

생성물은 저장소에 두지 않는다. 앱을 빌드할 때 만들어진다(`build/Ui.targets`).

## XML 과 SXML

SXML 은 XML 을 그대로 옮긴 Lisp 리스트다. 사람은 XML 로 읽고 쓰고, 생성기는 리스트로 다룬다.

```xml
<box padding="10 4" radius="13" fill="bar-deep">
  <row spacing="6">
    <dot size="8" fill="on ? live : on-bar-dim"/>
    <label text="text" size="12" color="on-bar"/>
  </row>
</box>
```

읽으면(`guile -L gen gen/main.scm ui.xml sxml`):

```scheme
(box (@ (radius "13") (padding "10 4") (fill "bar-deep"))
     (row (@ (spacing "6"))
          (dot (@ (size "8") (fill "on ? live : on-bar-dim")))
          (label (@ (text "text") (size "12") (color "on-bar")))))
```

`(태그 (@ (속성 값) ...) 자식 ...)` 꼴이다. 검사를 지나면(`... ui.xml checked`) 문자열이던 값의 뜻이 정해지고, 안 적은 속성은 기본값으로 채워진다.

```scheme
(dot (@ (size (num 8))
        (fill (if on (token live) (token on-bar-dim)))
        (tap #f)
        (visible (flag #t))))
```

생성기는 이 트리를 따라 내려가며 코드를 찍는다. 예를 들어 Android 쪽 `dot` 은 이 한 줄이다(`gen/android.scm`).

```scheme
((dot)
 (line "        var ~a = new View(context) { Background = Fill(~a, 0, oval: true) };" v (value (a 'fill))))
```

## 명세

요소는 넷뿐이다 — 필요해지면 스키마(`gen/spec.scm` 의 `elements`)에 한 줄 더하고 생성기 둘에 그리는 법을 더한다.

| 요소 | 뜻 | 속성 |
|---|---|---|
| `row` | 가로로 늘어놓기 | `spacing` |
| `box` | 둥근 상자(자식 하나까지) | `padding` `radius` `fill` |
| `dot` | 동그라미 | `size` `fill` |
| `label` | 글자 | `text` `size` `color` `bold` |

어느 요소에나: `tap`(누르면 나는 event), `visible`(보일지).

값은 셋 중 하나다.

- 이름 — 선언한 `prop` 이나 `color`
- 글자 그대로 — 숫자, `#RRGGBB`, `true`/`false`, `'따옴표 글자'`
- `조건 ? 값 : 값` — 조건은 flag prop

## 틀리면 드러난다

**명세가 틀리면 생성 단계에서** — 어느 부품의 어느 요소인지와 함께 빌드 오류가 된다.

```
ui.xml : error UI0001: status-chip > box 의 fill: "bar-dep" 는 color 값이 아니다 — 선언한 이름도, 글자 그대로의 값도 아니다
ui.xml : error UI0001: tab-header > box > row > label 의 text: text 자리인데 accent 은(는) color prop 이다
ui.xml : error UI0001: status-chip > box: 모르는 속성 raduis
ui.xml : error UI0001: bar-button: badge 을(를) 선언만 하고 쓰지 않았다
```

**명세가 바뀌면 앱 컴파일에서** — 부품의 prop · event 는 모두 C# `required` 멤버로 생성된다. 명세에 하나 더하면, 그 부품을 쓰는 곳이 채울 때까지 두 앱 모두 컴파일되지 않는다.

```xml
<component name="status-chip">
  <prop name="count" type="text"/>   <!-- 더하면 -->
```

```
src/Avalonia/Program.cs(19,33):      error CS9035: Required member 'StatusChip.Count' must be set in the object initializer
src/Android/MainActivity.cs(32,21): error CS9035: Required member 'StatusChip.Count' must be set in the object initializer
```

이름을 바꾸거나 지워도 쓰던 곳에서 오류가 난다. 오류가 나지 않는 것은 앱이 손댈 게 없는 변화뿐이다 — 색 값 · 모양을 고치는 것, 아직 아무도 쓰지 않는 부품이나 색을 더하는 것.

## 같은 명세, 다른 코드

두 프레임워크는 UI 를 만드는 방식부터 다르다. 생성기도 그 차이를 따른다.

Avalonia — 요소 하나가 객체 초기화 식 하나(식 안에 식). 아래는 일부 줄인 것:

```csharp
new Border
{
    Padding = new Thickness(10, 4, 10, 4),
    CornerRadius = new CornerRadius(13),
    Background = new SolidColorBrush(Tokens.BarDeep),
    Child =
        new StackPanel { ... Children = { new Ellipse { ... }, new TextBlock { ... } } }
}
```

Android — 요소 하나가 문장 여러 줄(만들고, 설정하고, 부모에 붙인다). 아래는 일부 줄인 것:

```csharp
var v1 = new FrameLayout(context);
v1.SetPadding(Px(10), Px(4), Px(10), Px(4));
v1.Background = Fill(Tokens.BarDeep, Px(13), oval: false);
var v2 = new LinearLayout(context) { Orientation = Orientation.Horizontal };
...
v1.AddView(v2, new FrameLayout.LayoutParams(Wrap, Wrap) { Gravity = GravityFlags.Center });
```

## 구조

```
ui.xml              명세 — 색과 부품(홈 표시 · 탭 · 기호 버튼 · 상태 칩)
gen/                생성기(Guile Scheme, 모두 약 530줄)
  spec.scm            XML 읽기, 스키마, 검사 · 값 풀기
  csharp.scm          두 플랫폼 공통(C#): 이름 바꾸기, 값 → 식, prop · event 선언
  avalonia.scm        Avalonia 컨트롤
  android.scm         Android 뷰
  main.scm            입구
build/Ui.targets    앱 빌드 때 생성기를 돌린다(명세나 생성기가 바뀌었을 때만)
src/Avalonia/       데모 앱 — 생성된 부품으로 상단 바를 짠다
src/Android/        같은 데모 앱
```

부품을 어디에 놓고 눌렸을 때 무엇을 할지는 앱(C#)이 정한다. 명세는 부품의 모양과, 부품이 받는 값 · 내는 일만 담는다.

## 빌드

[GNU Guile](https://www.gnu.org/software/guile/) 3 이 PATH 에 있어야 한다(`brew install guile`).

```sh
dotnet run --project src/Avalonia
dotnet build src/Android -c Release
```

생성기만 따로:

```sh
guile -L gen gen/main.scm ui.xml sxml        # 읽은 그대로
guile -L gen gen/main.scm ui.xml checked     # 검사를 지난 트리
guile -L gen gen/main.scm ui.xml avalonia    # Avalonia C#
guile -L gen gen/main.scm ui.xml android     # Android C#
```

## 확인한 것과 아닌 것

- 확인: 맥에서 Avalonia 앱 실행(창을 그림으로 떠서 확인), arm64 Android 에뮬레이터에서 탭 열기 · 닫기 · 전환 · 상태 토글, 위의 오류들
- 확인하지 않음: Windows · Linux 에서의 빌드와 실행(Guile 은 Windows 에서 쓰기 번거롭다), IDE 에서 생성물이 보이는지
- 부품은 값이 바뀔 때마다 통째로 다시 그린다 — PoC 라 단순하게 두었다

## 라이선스

MIT

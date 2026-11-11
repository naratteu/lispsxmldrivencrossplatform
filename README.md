# lispsxmldrivencrossplatform

UI 를 자체 스키마의 XML 로 적고, Lisp 가 그것을 SXML 로 읽어 플랫폼별 네이티브 UI 코드를 생성하는 PoC.
[fsharpdsldrivencrossplatform](https://github.com/naratteu/fsharpdsldrivencrossplatform) 의 후속 — 명세를 F# 코드에서 XML 로 옮기고, 생성기를 Lisp 로 바꿨다.

같은 `ui.xml` 에서 셋이 나온다.

- **Avalonia** 컨트롤(C#) — 데스크톱
- **Android** 뷰(C#) — .NET Android
- **프리뷰**(HTML) — 플랫폼 중립. 명세를 저장하면 바로 바뀐다

Lisp 는 [dotcl](https://github.com/dotcl/dotcl)(.NET 위의 Common Lisp)이라 .NET 밖의 도구가 필요 없다.

## 흐름

```
ui.xml ──읽기──▶ SXML ──검사 · 값 풀기──▶ 검사를 지난 트리 ──┬─▶ avalonia.lisp ─▶ Avalonia C# ┐
 사람이 읽고 쓴다   리스트    스키마에 안 맞으면 여기서 오류          ├─▶ android.lisp  ─▶ Android C#  ┴ 소스 생성기가 컴파일에 넣는다
                                                             └─▶ html.lisp     ─▶ 프리뷰
```

생성물은 저장소에 두지 않는다. 앱을 빌드하면 `obj/gen/` 에 남아 볼 수 있다.

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

읽으면(`dotnet dotcl gen/main.lisp ui.xml sxml`):

```lisp
(box (@ (padding "10 4") (radius "13") (fill "bar-deep"))
 (row (@ (spacing "6"))
  (dot (@ (size "8") (fill "on ? live : on-bar-dim")))
  (label (@ (text "text") (size "12") (color "on-bar")))))
```

`(태그 (@ (속성 값) ...) 자식 ...)` 꼴이다. 검사를 지나면(`... ui.xml checked`) 문자열이던 값의 뜻이 정해지고, 안 적은 속성은 기본값으로 채워진다.

```lisp
(dot (@ (size (num 8))
        (fill (if on (token live) (token on-bar-dim)))
        (tap nil)
        (visible (flag t))))
```

생성기는 이 트리를 따라 내려가며 코드를 찍는다. 예를 들어 Android 쪽 `dot` 은 이 한 줄이다(`gen/android.lisp`).

```lisp
(dot
 (line "        var ~a = new View(context) { Background = Fill(~a, 0, oval: true) };" v (android-value (a 'fill))))
```

## 명세

요소는 넷뿐이다 — 필요해지면 스키마(`gen/spec.lisp` 의 `*elements*`)에 한 줄 더하고 생성기마다 그리는 법을 더한다.

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

부품에는 `example`(prop 값을 채운 보기)을 적는다. 프리뷰와, 앱의 보기 모음 화면에 나온다.

```xml
<component name="status-chip" doc="상태 표시 — 점과 글자" backdrop="bar">
  <prop name="text" type="text"/>
  <prop name="on" type="flag"/>
  <example text="'연결됨'" on="true"/>
  <example text="'대기'" on="false"/>
  ...
```

## 프리뷰

```sh
dotnet dotcl gen/main.lisp ui.xml serve     # http://localhost:8090/
```

- `ui.xml` 을 저장하면 브라우저가 스스로 바뀐다. 명세가 틀리면 그 자리에 줄 번호와 까닭이 나온다
- 생성기(`gen/*.lisp`)를 고쳐도 서버를 끄지 않고 바로 반영된다
- 부품을 누르면 어떤 event 가 나는지 보여 준다

프리뷰는 네이티브 코드를 거치지 않는다 — 같은 트리를 HTML 로 그리는 세 번째 생성기다(`gen/html.lisp`).

### 프리뷰를 기준으로 플랫폼 맞추기

같은 보기를 세 곳에서 그려 크기를 잰다. 프리뷰는 주소 끝에 `#plain`, Avalonia 는 `--gallery`, Android 는 `--ez gallery true` 로 보기만 늘어놓은 화면이 뜨고, 앱은 잰 크기를 찍는다.

처음 잰 값(dp, 가로×세로):

| 보기 | 프리뷰 | Avalonia | Android |
|---|---|---|---|
| home-mark | 40×40 | 40×40 | 40×40 |
| tab-header(보는 탭) | 80.2×30 | 81×29 | 83×32 |
| bar-button `+` | 28×31 | 28×28 | 27.5×31.5 |
| status-chip | 65.1×24 | 66×23 | 67×25.5 |

글자가 없는 부품은 같고, 차이는 글꼴마다 다른 줄 높이에서 났다. 줄 높이를 글꼴에 맡기지 않고 명세의 뜻으로 정해(글자 크기의 1.4배, `spec.lisp` 의 `line-height`) 세 생성기에 넣은 뒤:

| 보기 | 프리뷰 | Avalonia | Android |
|---|---|---|---|
| home-mark | 40×40 | 40×40 | 40×40 |
| tab-header(보는 탭) | 80.2×32 | 81×32 | 83×32 |
| bar-button `+` | 28×36 | 28×36 | 27.5×36 |
| status-chip | 65.1×25 | 66×25 | 67×25 |

높이는 같아졌다. 남은 차이는 글꼴이 달라 생기는 글자 폭(3dp 안쪽)과 기호 모양(`↻` 은 글꼴에 따라 29~36dp)이다 — 같은 글꼴을 싣지 않는 한 남는다. 재는 것은 아직 손으로 돌린다.

## 틀리면 드러난다

**명세가 틀리면 생성 단계에서** — 명세의 줄 번호와 함께 컴파일 오류가 된다.

```
ui.xml(66,1): error UI0001: status-chip > box 의 fill: "bar-dep" 는 color 값이 아니다 — 선언한 이름도, 글자 그대로의 값도 아니다
```

모르는 요소 · 속성, 종류가 안 맞는 값(text 자리에 color prop), 선언만 하고 쓰지 않은 prop · event 도 같은 식으로 잡힌다.

**명세가 바뀌면 앱 컴파일에서** — 부품의 prop · event 는 모두 C# `required` 멤버로 생성된다. 명세에 하나 더하면, 그 부품을 쓰는 곳이 채울 때까지 두 앱 모두 컴파일되지 않는다.

```
src/Avalonia/Program.cs(19,33):      error CS9035: Required member 'StatusChip.Count' must be set in the object initializer
src/Android/MainActivity.cs(32,21): error CS9035: Required member 'StatusChip.Count' must be set in the object initializer
```

이름을 바꾸거나 지워도 쓰던 곳에서 오류가 난다. 오류가 나지 않는 것은 앱이 손댈 게 없는 변화뿐이다 — 색 값 · 모양을 고치는 것, 아직 아무도 쓰지 않는 부품이나 색을 더하는 것.

## 같은 명세, 다른 코드

두 프레임워크는 UI 를 만드는 방식부터 다르다. 생성기도 그 차이를 따른다. 아래는 일부 줄인 것.

Avalonia — 요소 하나가 객체 초기화 식 하나(식 안에 식):

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

Android — 요소 하나가 문장 여러 줄(만들고, 설정하고, 부모에 붙인다):

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
gen/                생성기(Common Lisp, 약 790줄)
  spec.lisp           XML 읽기(System.Xml.Linq), 스키마, 검사 · 값 풀기
  csharp.lisp         두 플랫폼 공통(C#): 이름 바꾸기, 값 → 식, prop · event 선언, 보기 모음
  avalonia.lisp       Avalonia 컨트롤
  android.lisp        Android 뷰
  html.lisp           프리뷰
  main.lisp           입구, 프리뷰 서버
build/
  SourceGen/          소스 생성기 — 컴파일러 안에서 dotcl 로 main.lisp 를 돌리는 껍데기(C# 94줄)
  Ui.targets          앱이 가져다 쓴다: 명세 · 생성기를 소스 생성기에 넘긴다
src/Avalonia/       데모 앱 — 생성된 부품으로 상단 바를 짠다
src/Android/        같은 데모 앱
```

부품을 어디에 놓고 눌렸을 때 무엇을 할지는 앱(C#)이 정한다. 명세는 부품의 모양과, 부품이 받는 값 · 내는 일만 담는다.

소스 생성기는 [dartk](https://github.com/dartk) 의 `csharp-sourcegen-fsx` 와 같은 방식이다 — 생성기 안에서 스크립트 처리기를 프로세스로 띄우고, 찍혀 나온 것을 소스로 넣는다. 소스 생성기에서 프로세스를 띄우는 것은 권장되지 않는 우회다(RS1035).

## 빌드

```sh
dotnet tool restore                          # dotcl
dotnet run --project src/Avalonia
dotnet build src/Android -c Release
```

생성기만 따로:

```sh
dotnet dotcl gen/main.lisp ui.xml sxml        # 읽은 그대로
dotnet dotcl gen/main.lisp ui.xml checked     # 검사를 지난 트리
dotnet dotcl gen/main.lisp ui.xml avalonia    # Avalonia C#
dotnet dotcl gen/main.lisp ui.xml android     # Android C#
dotnet dotcl gen/main.lisp ui.xml html        # 프리뷰 HTML
```

## 확인한 것과 아닌 것

- 확인: 맥에서 Avalonia 앱 실행(창을 그림으로 떠서 확인), arm64 Android 에뮬레이터에서 탭 열기 · 닫기 · 전환 · 상태 토글, 프리뷰 서버(저장하면 갱신 · 생성기 고쳐도 갱신 · 오류 표시), 위의 오류들과 크기 비교
- 확인: 처음에는 생성기를 Guile(Scheme)로 짰고, dotcl 로 옮긴 뒤 두 플랫폼 출력이 한 글자도 다르지 않았다
- 확인하지 않음: Windows · Linux 에서의 빌드와 실행, IDE 안에서의 동작(저장할 때 다시 생성되는지, 오류가 명세 줄에 표시되는지)
- 명세가 틀리면 생성물이 없어서, 명세 오류 뒤에 "Ui 를 찾을 수 없다"는 오류가 함께 나온다
- 부품은 값이 바뀔 때마다 통째로 다시 그린다 — PoC 라 단순하게 두었다

## 라이선스

MIT

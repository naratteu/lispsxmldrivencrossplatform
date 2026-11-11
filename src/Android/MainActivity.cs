using Android.Graphics;
using Android.Util;
using Android.Views;
using Android.Widget;
using Ui;

namespace Demo;

/// 생성된 부품(Ui.*)으로 상단 바를 짠다 — 어디에 놓고 눌렸을 때 무엇을 할지는 앱이 정한다
[Activity(Label = "lispsxmldrivencrossplatform", MainLauncher = true, Theme = "@android:style/Theme.Material.Light.NoActionBar")]
public sealed class MainActivity : Activity
{
    static readonly (string Name, Color Accent)[] Items =
        [("작업", Tokens.Blue), ("재고", Tokens.Green), ("품질", Tokens.Orange), ("출하", Tokens.Violet)];

    LinearLayout _tabs = null!;
    BarButton _add = null!;
    StatusChip _chip = null!;
    TextView _page = null!;
    readonly List<int> _open = [0, 1];
    int? _active = 0;

    protected override void OnCreate(Bundle? saved)
    {
        base.OnCreate(saved);
        var dp = Resources!.DisplayMetrics!.Density;

        var home = new HomeMark(this) { Clicked = () => Show(null) };
        _tabs = new LinearLayout(this) { Orientation = Orientation.Horizontal };
        _tabs.SetGravity(GravityFlags.CenterVertical);
        _add = new BarButton(this) { Glyph = "+", On = true, Clicked = OpenNext };
        _chip = new StatusChip(this) { Text = "대기", On = false };
        var toggle = new BarButton(this) { Glyph = "↻", On = true, Clicked = () => { _chip.On = !_chip.On; _chip.Text = _chip.On ? "연결됨" : "대기"; } };

        var bar = new LinearLayout(this) { Orientation = Orientation.Horizontal };
        bar.SetGravity(GravityFlags.CenterVertical);
        bar.SetBackgroundColor(Tokens.Bar);
        bar.SetPadding((int)(4 * dp), 0, (int)(4 * dp), 0);
        bar.AddView(home);
        bar.AddView(_tabs);
        bar.AddView(_add);
        bar.AddView(new Space(this), new LinearLayout.LayoutParams(0, 1, 1f));
        bar.AddView(_chip);
        bar.AddView(toggle);

        _page = new TextView(this) { Gravity = GravityFlags.Center };
        _page.SetTextSize(ComplexUnitType.Dip, 28);
        _page.SetBackgroundColor(Tokens.Page);

        var root = new LinearLayout(this) { Orientation = Orientation.Vertical };
        root.SetFitsSystemWindows(true);   // 상태 바 · 내비게이션 바 밑으로 들어가지 않게
        root.SetBackgroundColor(Tokens.Bar);
        root.AddView(bar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MatchParent, (int)(44 * dp)));
        root.AddView(_page, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MatchParent, 0, 1f));
        SetContentView(root);
        Show(_active);
    }

    void Show(int? item)
    {
        _active = item;
        _tabs.RemoveAllViews();
        foreach (var i in _open)
            _tabs.AddView(new TabHeader(this)
            {
                Title = Items[i].Name,
                Accent = Items[i].Accent,
                Active = i == _active,
                Clicked = () => Show(i),
                CloseClicked = () => Close(i),
            });
        _add.Visibility = _open.Count < Items.Length ? ViewStates.Visible : ViewStates.Gone;
        _page.Text = item is { } a ? Items[a].Name : "홈";
        _page.SetTextColor(item is { } b ? Items[b].Accent : Tokens.TextSecondary);
    }

    void OpenNext()
    {
        var next = Enumerable.Range(0, Items.Length).First(i => !_open.Contains(i));
        _open.Add(next);
        Show(next);
    }

    void Close(int item)
    {
        var at = _open.IndexOf(item);
        _open.Remove(item);
        Show(_open.Count == 0 ? null : _open[Math.Min(at, _open.Count - 1)]);
    }
}

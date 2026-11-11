using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Themes.Fluent;
using Ui;

namespace Demo;

/// 생성된 부품(Ui.*)으로 상단 바를 짠다 — 어디에 놓고 눌렸을 때 무엇을 할지는 앱이 정한다
sealed class MainWindow : Window
{
    static readonly (string Name, Color Accent)[] Items =
        [("작업", Tokens.Blue), ("재고", Tokens.Green), ("품질", Tokens.Orange), ("출하", Tokens.Violet)];

    readonly StackPanel _tabs = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    readonly BarButton _add;
    readonly StatusChip _chip = new() { Text = "대기", On = false };
    readonly TextBlock _page = new() { FontSize = 28, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    readonly List<int> _open = [0, 1];
    int? _active = 0;

    public MainWindow()
    {
        Title = "lispsxmldrivencrossplatform";
        Width = 900;
        Height = 420;
        Background = new SolidColorBrush(Tokens.Page);

        var home = new HomeMark { Clicked = () => Show(null) };
        _add = new BarButton { Glyph = "+", On = true, Clicked = OpenNext };
        var toggle = new BarButton { Glyph = "↻", On = true, Clicked = () => { _chip.On = !_chip.On; _chip.Text = _chip.On ? "연결됨" : "대기"; } };

        var left = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 0), Children = { home, _tabs, _add } };
        var right = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 0), Children = { _chip, toggle } };
        Grid.SetColumn(right, 1);
        var bar = new Grid { Height = 44, Background = new SolidColorBrush(Tokens.Bar), ColumnDefinitions = new("*,Auto"), Children = { left, right } };
        DockPanel.SetDock(bar, Dock.Top);
        Content = new DockPanel { Children = { bar, _page } };
        Show(_active);
    }

    void Show(int? item)
    {
        _active = item;
        _tabs.Children.Clear();
        foreach (var i in _open)
            _tabs.Children.Add(new TabHeader
            {
                Title = Items[i].Name,
                Accent = Items[i].Accent,
                Active = i == _active,
                Clicked = () => Show(i),
                CloseClicked = () => Close(i),
            });
        _add.IsVisible = _open.Count < Items.Length;
        _page.Text = item is { } a ? Items[a].Name : "홈";
        _page.Foreground = new SolidColorBrush(item is { } b ? Items[b].Accent : Tokens.TextSecondary);
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

sealed class App : Application
{
    public override void Initialize() => Styles.Add(new FluentTheme());

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            desktop.MainWindow = new MainWindow();
        base.OnFrameworkInitializationCompleted();
    }
}

static class Program
{
    [STAThread]
    static int Main(string[] args) =>
        AppBuilder.Configure<App>().UsePlatformDetect().StartWithClassicDesktopLifetime(args);
}

using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace Evoo.Windows;

/// <summary>
/// The floating pill at the bottom of the screen: a red dot and moving bars while you speak, dots while Evoo
/// writes, a short message when something needs saying. It never takes focus and clicks pass through it.
/// </summary>
internal sealed class PillWindow : Window
{
    private readonly Ellipse dot = new() { Width = 8, Height = 8, Fill = new SolidColorBrush(Color.FromRgb(0xFF, 0x4D, 0x4D)), Margin = new Thickness(0, 0, 9, 0), VerticalAlignment = VerticalAlignment.Center };
    private readonly StackPanel bars = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock label = new() { Foreground = Brushes.White, FontSize = 12.5, FontWeight = FontWeights.Medium, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 360 };
    private readonly DispatcherTimer hideTimer = new();
    private readonly float[] levels = new float[14];

    public PillWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        ResizeMode = ResizeMode.NoResize;
        SizeToContent = SizeToContent.WidthAndHeight;

        for (var i = 0; i < levels.Length; i++)
            bars.Children.Add(new Rectangle { Width = 3, Height = 4, RadiusX = 1.5, RadiusY = 1.5, Fill = Brushes.White, Margin = new Thickness(1.5, 0, 1.5, 0), VerticalAlignment = VerticalAlignment.Center });

        var row = new StackPanel { Orientation = Orientation.Horizontal, Height = 26 };
        row.Children.Add(dot);
        row.Children.Add(bars);
        row.Children.Add(label);
        Content = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xEB, 0x0F, 0x11, 0x15)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(20),
            Padding = new Thickness(16, 6, 16, 6),
            Margin = new Thickness(10), // room for nothing to be clipped at the rounded edge
            Child = row,
        };
        SizeChanged += (_, _) => Place();
        hideTimer.Tick += (_, _) => { hideTimer.Stop(); Hide(); };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        // Never activate, never catch the mouse, stay out of Alt+Tab.
        var handle = new WindowInteropHelper(this).Handle;
        var style = Native.GetWindowLongPtr(handle, Native.GWL_EXSTYLE).ToInt64();
        Native.SetWindowLongPtr(handle, Native.GWL_EXSTYLE,
            new IntPtr(style | Native.WS_EX_NOACTIVATE | Native.WS_EX_TRANSPARENT | Native.WS_EX_TOOLWINDOW));
    }

    private void Place()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - ActualWidth) / 2;
        Top = area.Bottom - ActualHeight - 14;
    }

    private void Present(bool showDot, bool showBars, string text)
    {
        hideTimer.Stop();
        dot.Visibility = showDot ? Visibility.Visible : Visibility.Collapsed;
        bars.Visibility = showBars ? Visibility.Visible : Visibility.Collapsed;
        label.Text = text;
        label.Margin = new Thickness(text.Length > 0 && (showDot || showBars) ? 10 : 0, 0, 0, 0);
        label.Visibility = text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (!IsVisible) Show();
        Place();
    }

    public void ShowListening()
    {
        Array.Clear(levels);
        Present(true, true, "");
    }

    public void ShowWorking() => Present(false, false, "Writing…");

    /// <summary>A short note ("Didn't catch that") that goes away by itself.</summary>
    public void ShowMessage(string text, double seconds = 2.5)
    {
        Present(false, false, text);
        hideTimer.Interval = TimeSpan.FromSeconds(seconds);
        hideTimer.Start();
    }

    public void HidePill()
    {
        hideTimer.Stop();
        Hide();
    }

    /// <summary>Feeds the bars: each new loudness value pushes the older ones along.</summary>
    public void SetLevel(float level)
    {
        if (bars.Visibility != Visibility.Visible) return;
        Array.Copy(levels, 1, levels, 0, levels.Length - 1);
        levels[^1] = level;
        for (var i = 0; i < levels.Length; i++)
            ((Rectangle)bars.Children[i]).Height = 4 + levels[i] * 20;
    }
}

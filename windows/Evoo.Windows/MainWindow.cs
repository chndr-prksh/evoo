using System;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Evoo.Speech;

namespace Evoo.Windows;

/// <summary>Setup and settings: download the speech model, how to dictate, a box to try it, start at sign-in.</summary>
internal sealed class MainWindow : Window
{
    private static readonly Brush Ink = new SolidColorBrush(Color.FromRgb(0x0F, 0x11, 0x15));
    private static readonly Brush Muted = new SolidColorBrush(Color.FromRgb(0x66, 0x6B, 0x75));
    private static readonly Brush Soft = new SolidColorBrush(Color.FromRgb(0xF6, 0xF7, 0xF9));
    private static readonly Brush Line = new SolidColorBrush(Color.FromRgb(0xE7, 0xE8, 0xEC));

    private readonly TextBlock modelTitle = Title2("1 · Speech model");
    private readonly TextBlock modelBody = Body("A one-time 670 MB download. After that Evoo works offline.");
    private readonly ProgressBar modelProgress = new() { Height = 6, Maximum = 1, Margin = new Thickness(0, 10, 0, 0), Visibility = Visibility.Collapsed };
    private readonly Button modelButton = PrimaryButton("Download");
    private readonly TextBlock micBody = Body("");
    public TextBox TryBox { get; } = new()
    {
        AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinHeight = 90, FontSize = 15, Padding = new Thickness(10),
        BorderBrush = Line, Margin = new Thickness(0, 10, 0, 0), VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
    };

    public MainWindow()
    {
        Title = "Evoo";
        Width = 560;
        Height = 760;
        MinWidth = 440;
        Background = Brushes.White;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = new FontFamily("Segoe UI Variable, Segoe UI");

        var page = new StackPanel { Margin = new Thickness(28, 24, 28, 28) };
        page.Children.Add(new TextBlock { Text = "Evoo", FontSize = 32, FontWeight = FontWeights.Bold, Foreground = Ink });
        page.Children.Add(Body("Hold Ctrl + Win, speak, let go. Voice typing in any app — free, and entirely on this PC. (Preview)", 15));

        modelButton.Click += async (_, _) => await DownloadAsync();
        page.Children.Add(Card(modelTitle, modelBody, modelProgress, modelButton));

        var micButton = SecondaryButton("Open microphone settings");
        micButton.Click += (_, _) => Open("ms-settings:privacy-microphone");
        page.Children.Add(Card(Title2("2 · Microphone"), micBody, micButton));

        page.Children.Add(Card(Title2("3 · Dictate"),
            Body("Click into any text box, hold Ctrl + Win, and speak. Let go and the text is typed there. Press Esc while holding to cancel.\n\nChange your mind mid-sentence and Evoo keeps the final version: “Let's meet tomorrow, no, day after tomorrow.”"),
            Body("Try it here:", 13), TryBox));

        var startup = new CheckBox { Content = "Start Evoo when I sign in to Windows", IsChecked = Startup.IsEnabled, Margin = new Thickness(0, 4, 0, 0), FontSize = 14 };
        startup.Click += (_, _) => { try { Startup.IsEnabled = startup.IsChecked == true; } catch { } };
        page.Children.Add(Card(Title2("Settings"), startup));

        page.Children.Add(Body("Your voice never leaves this PC: no account, no cloud. The internet is used once, to download the speech model. " +
            "Speech: NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0) via sherpa-onnx (Apache-2.0). Evoo is open source (Apache-2.0).\n" +
            "Evoo " + (typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? ""), 12));

        Content = new ScrollViewer { Content = page, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Refresh();
    }

    /// <summary>Closing the window keeps Evoo running in the tray.</summary>
    protected override void OnClosing(System.ComponentModel.CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }

    public void Refresh()
    {
        if (ModelStore.IsReady)
        {
            modelTitle.Text = "1 · Speech model  ✓";
            modelBody.Text = "Downloaded. Evoo now works offline.";
            modelButton.Visibility = Visibility.Collapsed;
            modelProgress.Visibility = Visibility.Collapsed;
        }
        micBody.Text = Recorder.DeviceCount > 0
            ? "Evoo listens only while you hold Ctrl + Win. If nothing is heard, check that Windows lets desktop apps use the microphone."
            : "No microphone found. Plug one in, or check that Windows lets desktop apps use the microphone.";
    }

    private bool downloading;

    private async Task DownloadAsync()
    {
        if (downloading) return;
        downloading = true;
        modelButton.Visibility = Visibility.Collapsed;
        modelProgress.Visibility = Visibility.Visible;
        try
        {
            var progress = new Progress<double>(p =>
            {
                modelProgress.Value = p;
                modelBody.Text = $"Downloading… {(int)(p * 100)}% of 670 MB. You can keep working; this window can be closed.";
            });
            await Task.Run(() => ModelStore.DownloadAsync(progress));
        }
        catch (Exception e)
        {
            modelBody.Text = "The download didn't finish: " + e.Message + " It continues from where it stopped.";
            modelButton.Content = "Try again";
            modelButton.Visibility = Visibility.Visible;
            modelProgress.Visibility = Visibility.Collapsed;
        }
        downloading = false;
        Refresh();
    }

    private static void Open(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
    }

    private static TextBlock Title2(string text) => new() { Text = text, FontSize = 17, FontWeight = FontWeights.SemiBold, Foreground = Ink };

    private static TextBlock Body(string text, double size = 14) =>
        new() { Text = text, FontSize = size, Foreground = Muted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 5, 0, 0), LineHeight = size * 1.45 };

    private static Button PrimaryButton(string text) => new()
    {
        Content = text, Background = Ink, Foreground = Brushes.White, BorderThickness = new Thickness(0), FontSize = 14, FontWeight = FontWeights.SemiBold,
        Padding = new Thickness(18, 8, 18, 8), Margin = new Thickness(0, 12, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, Cursor = System.Windows.Input.Cursors.Hand,
    };

    private static Button SecondaryButton(string text) => new()
    {
        Content = text, Background = Brushes.White, Foreground = Ink, BorderBrush = Line, FontSize = 13.5,
        Padding = new Thickness(14, 7, 14, 7), Margin = new Thickness(0, 12, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, Cursor = System.Windows.Input.Cursors.Hand,
    };

    private static Border Card(params UIElement[] children)
    {
        var stack = new StackPanel();
        foreach (var child in children) stack.Children.Add(child);
        return new Border { Background = Soft, BorderBrush = Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(18), Margin = new Thickness(0, 14, 0, 0), Child = stack };
    }
}

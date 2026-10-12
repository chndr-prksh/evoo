using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using Evoo.Core;
using Evoo.Speech;

namespace Evoo.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var selfTest = Array.IndexOf(args, "--self-test");
        if (selfTest >= 0) return SelfTest(selfTest + 1 < args.Length ? args[selfTest + 1] : "evoo-self-test.txt");

        var shots = Array.IndexOf(args, "--screenshots");
        if (shots >= 0) return Screenshots(shots + 1 < args.Length ? args[shots + 1] : "screenshots");

        // One Evoo at a time: a second copy would fight over the keyboard and microphone.
        using var single = new Mutex(true, "Evoo.Windows.SingleInstance", out var first);
        if (!first) return 0;

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var controller = new AppController();
        app.Startup += (_, _) => controller.Start(background: args.Contains("--background"));
        return app.Run();
    }

    /// <summary>
    /// Pictures of the real app, drawn by the app itself: the setup window and the pill in each of its states.
    /// Used for the website; run by the automated build on Windows.
    /// </summary>
    private static int Screenshots(string folder)
    {
        Directory.CreateDirectory(folder);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        void Settle() => System.Windows.Threading.Dispatcher.CurrentDispatcher.Invoke(() => { }, System.Windows.Threading.DispatcherPriority.ApplicationIdle);

        var window = new MainWindow();
        window.Show();
        window.TryBox.Text = "Let's meet day after tomorrow at 4 PM. ";
        Settle();
        Save(window.Page, System.Windows.Media.Brushes.White, 28, Path.Combine(folder, "setup.png"));
        window.Hide();

        var pill = new PillWindow();
        var wave = new[] { 0.2f, 0.5f, 0.9f, 0.6f, 0.3f, 0.7f, 1f, 0.55f, 0.25f, 0.6f, 0.85f, 0.45f, 0.3f, 0.5f };
        void Shot(string name, Action state)
        {
            state();
            Settle();
            Save(pill.Body, null, 0, Path.Combine(folder, name));
        }
        Shot("pill-listening.png", () => { pill.ShowListening(); foreach (var level in wave) pill.SetLevel(level); });
        Shot("pill-command.png", () => { pill.ShowListening(command: true); foreach (var level in wave) pill.SetLevel(level); });
        Shot("pill-writing.png", () => pill.ShowWorking());
        Shot("pill-polishing.png", () => pill.ShowWorking("Polishing…"));
        Shot("pill-step.png", () => pill.ShowWorking("1/2 · Close the tab"));
        Shot("pill-done.png", () => pill.ShowMessage("Close the tab → Switch to Chrome"));
        Shot("pill-volume.png", () => pill.ShowMessage("Volume 30%"));
        pill.HidePill();
        app.Shutdown();
        return 0;
    }

    private static void Save(FrameworkElement element, System.Windows.Media.Brush? background, double padding, string path)
    {
        element.UpdateLayout();
        const double scale = 2;
        double width = element.ActualWidth + padding * 2, height = element.ActualHeight + padding * 2;
        var visual = new System.Windows.Media.DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            if (background is not null) context.DrawRectangle(background, null, new Rect(0, 0, width, height));
            var brush = new System.Windows.Media.VisualBrush(element) { Stretch = System.Windows.Media.Stretch.None };
            context.DrawRectangle(brush, null, new Rect(padding, padding, element.ActualWidth, element.ActualHeight));
        }
        var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)Math.Ceiling(width * scale), (int)Math.Ceiling(height * scale),
            96 * scale, 96 * scale, System.Windows.Media.PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
        using var file = File.Create(path);
        encoder.Save(file);
    }

    /// <summary>
    /// For automated builds: starts each part of the app that can be checked without a person (rules, keyboard hook,
    /// windows, audio devices), writes what happened to a file, and exits. 0 = everything that must work did.
    /// </summary>
    private static int SelfTest(string reportPath)
    {
        var lines = new System.Collections.Generic.List<string>();
        var failed = false;
        void Check(string name, bool required, Func<string> run)
        {
            try { lines.Add($"ok    {name}: {run()}"); }
            catch (Exception e)
            {
                lines.Add($"{(required ? "FAIL " : "skip ")} {name}: {e.GetType().Name}: {e.Message}");
                if (required) failed = true;
            }
        }

        Check("rules", true, () =>
        {
            var got = EvooPipeline.Process("Let's meet tomorrow, no, day after tomorrow.");
            if (got != "Let's meet day after tomorrow.") throw new InvalidOperationException("got: " + got);
            return got;
        });
        Check("voice commands", true, () =>
        {
            var steps = CommandChain.Parts("Close the tab and switch to Notepad.", p => VoiceCommands.Parse(p, AppLauncher.IsApp) is not null);
            if (steps is not { Count: 2 }) throw new InvalidOperationException("the chain didn't split into two commands");
            return CommandChain.Summary(steps) + "; Notepad → " + AppLauncher.Resolve("notepad");
        });
        Check("polish engine", false, () => Polisher.IsAvailable
            ? "bundled" + (Polisher.IsModelReady ? ", model present" : ", no model yet")
            : throw new FileNotFoundException("llama-server.exe is not next to Evoo.exe"));
        Check("model folder", true, () => ModelStore.Folder + (ModelStore.IsReady ? " (model present)" : " (no model yet)"));
        Check("keyboard hook", true, () =>
        {
            using var hook = new KeyboardHook();
            if (!hook.Install()) throw new InvalidOperationException("SetWindowsHookEx failed");
            return "installed and removed";
        });
        Check("windows", true, () =>
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var pill = new PillWindow();
            pill.ShowListening();
            pill.SetLevel(0.7f);
            pill.ShowWorking();
            pill.ShowMessage("Self-test");
            var size = $"{pill.ActualWidth:0}x{pill.ActualHeight:0}";
            pill.HidePill();
            var window = new MainWindow();
            window.Show();
            window.Refresh();
            var title = window.Title;
            window.Hide();
            app.Shutdown();
            return $"pill {size}, window \"{title}\"";
        });
        Check("tray icon", true, () => { using var icon = AppIcon.Load(); return $"{icon.Width}x{icon.Height}"; });
        Check("microphones", false, () => Recorder.DeviceCount + " found");
        Check("start at sign-in", false, () => "currently " + (Startup.IsEnabled ? "on" : "off"));

        lines.Add(failed ? "SELF-TEST FAILED" : "SELF-TEST OK");
        try { File.WriteAllLines(reportPath, lines); } catch { }
        return failed ? 1 : 0;
    }
}

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

        // One Evoo at a time: a second copy would fight over the keyboard and microphone.
        using var single = new Mutex(true, "Evoo.Windows.SingleInstance", out var first);
        if (!first) return 0;

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var controller = new AppController();
        app.Startup += (_, _) => controller.Start(background: args.Contains("--background"));
        return app.Run();
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

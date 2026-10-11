using System;
using System.Threading.Tasks;
using System.Windows;
using Evoo.Core;
using Evoo.Speech;
using Forms = System.Windows.Forms;

namespace Evoo.Windows;

/// <summary>
/// Ties it together: hold Ctrl + Win → record → release → speech model → Evoo's rules → typed at the cursor.
/// Lives in the notification area; the window is only for setup.
/// </summary>
internal sealed class AppController : IDisposable
{
    private readonly KeyboardHook hook = new();
    private readonly Recorder recorder = new();
    private readonly SpeechEngine engine = new();
    private readonly PillWindow pill = new();
    private readonly MainWindow window = new();
    private Forms.NotifyIcon? tray;
    private bool busy;

    public void Start(bool background)
    {
        tray = new Forms.NotifyIcon
        {
            Icon = AppIcon.Load(),
            Text = "Evoo — hold Ctrl + Win to dictate",
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip(),
        };
        tray.ContextMenuStrip.Items.Add("Open Evoo", null, (_, _) => ShowWindow());
        tray.ContextMenuStrip.Items.Add("Quit", null, (_, _) => Quit());
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) ShowWindow(); };

        recorder.Level += level => pill.Dispatcher.BeginInvoke(() => pill.SetLevel(level));
        hook.HoldStarted += Begin;
        hook.HoldEnded += Finish;
        hook.Cancelled += Cancel;
        if (!hook.Install()) pill.ShowMessage("Evoo couldn't watch the keyboard — restart it", 5);

        // First run, or the model isn't there yet: show setup. Otherwise stay out of the way.
        if (!background || !ModelStore.IsReady) ShowWindow();
        if (ModelStore.IsReady) Task.Run(() => { try { engine.Load(); } catch { } }); // ready before the first hold
    }

    private void ShowWindow()
    {
        window.Refresh();
        window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate();
    }

    private void Begin()
    {
        if (busy) return;
        // With Win held, Windows would open the Start menu on release; one press of an unused key prevents that.
        Native.Send(Native.Key(Native.VK_MASK, false), Native.Key(Native.VK_MASK, true));
        if (!ModelStore.IsReady)
        {
            pill.ShowMessage("Download the speech model first — opening Evoo");
            ShowWindow();
            return;
        }
        try { recorder.Start(); }
        catch (Exception e)
        {
            pill.ShowMessage("Couldn't start the microphone: " + e.Message, 4);
            return;
        }
        pill.ShowListening();
        if (!engine.IsLoaded) Task.Run(() => { try { engine.Load(); } catch { } });
    }

    private void Cancel()
    {
        if (!recorder.IsRecording) return;
        recorder.Stop();
        pill.HidePill();
    }

    private async void Finish()
    {
        if (!recorder.IsRecording || busy) return;
        var samples = recorder.Stop();
        if (AudioStats.HasNoSpeech(samples)) { pill.HidePill(); return; }
        busy = true;
        pill.ShowWorking();
        try
        {
            var text = await Task.Run(() =>
            {
                engine.Load();
                return EvooPipeline.Process(engine.Transcribe(samples));
            });
            if (text.Length == 0) pill.ShowMessage("Didn't catch that");
            else
            {
                pill.HidePill();
                // Typing into Evoo's own try-it box needs no clipboard round trip.
                if (window.IsActive && window.TryBox.IsKeyboardFocused) window.TryBox.SelectedText = text + " ";
                else await Paster.PasteAsync(text + " ");
            }
        }
        catch (Exception e)
        {
            pill.ShowMessage("Something went wrong: " + e.Message, 4);
        }
        busy = false;
    }

    private void Quit()
    {
        Dispose();
        Application.Current.Shutdown();
    }

    public void Dispose()
    {
        hook.Dispose();
        recorder.Dispose();
        engine.Dispose();
        if (tray is not null) { tray.Visible = false; tray.Dispose(); tray = null; }
    }
}

internal static class AppIcon
{
    public static System.Drawing.Icon Load()
    {
        using var stream = typeof(AppIcon).Assembly.GetManifestResourceStream("evoo.ico");
        return stream is null ? System.Drawing.SystemIcons.Application : new System.Drawing.Icon(stream);
    }
}

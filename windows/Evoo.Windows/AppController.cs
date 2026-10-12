using System;
using System.Threading.Tasks;
using System.Windows;
using Evoo.Core;
using Evoo.Speech;
using Forms = System.Windows.Forms;

namespace Evoo.Windows;

/// <summary>
/// Ties it together: hold Ctrl + Win → record → release → speech model → a command is carried out, or the text
/// goes through Evoo's rules and the optional AI polish and is typed at the cursor.
/// Lives in the notification area; the window is only for setup.
/// </summary>
internal sealed class AppController : IDisposable
{
    private readonly KeyboardHook hook = new();
    private readonly Recorder recorder = new();
    private readonly SpeechEngine engine = new();
    private readonly Polisher polisher = new();
    private readonly PillWindow pill = new();
    private readonly MainWindow window = new();
    private Forms.NotifyIcon? tray;
    private bool busy;
    /// <summary>Ctrl + Win + Shift: everything said in this recording is a command, never typed.</summary>
    private bool commandMode;

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
        hook.CommandRequested += () =>
        {
            if (!recorder.IsRecording || commandMode || !Settings.Current.VoiceCommands) return;
            commandMode = true;
            pill.ShowListening(command: true);
        };
        if (!hook.Install()) pill.ShowMessage("Evoo couldn't watch the keyboard — restart it", 5);

        // First run, or the model isn't there yet: show setup. Otherwise stay out of the way.
        if (!background || !ModelStore.IsReady) ShowWindow();
        if (ModelStore.IsReady) Task.Run(() => { try { engine.Load(); } catch { } }); // ready before the first hold
        WarmPolish();
    }

    private bool PolishOn => Settings.Current.Polish && Polisher.IsAvailable && Polisher.IsModelReady;

    private void WarmPolish()
    {
        if (PolishOn) polisher.WarmUpAsync().ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted);
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
        commandMode = false;
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
        WarmPolish(); // ready by the time you finish speaking
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
        var asCommand = commandMode;
        pill.ShowWorking(asCommand ? "Working…" : "Writing…");
        try
        {
            var heard = await Task.Run(() =>
            {
                engine.Load();
                return TextCleaner.Clean(engine.Transcribe(samples));
            });
            if (heard.Length == 0) pill.ShowMessage("Didn't catch that");
            else if (Settings.Current.VoiceCommands && await RunCommandsAsync(heard)) { }
            else if (asCommand) pill.ShowMessage("Not a command I know: “" + (heard.Length > 60 ? heard[..60] + "…" : heard) + "”", 3.5);
            else await TypeAsync(heard);
        }
        catch (Exception e)
        {
            pill.ShowMessage("Something went wrong: " + e.Message, 4);
        }
        busy = false;
    }

    /// <summary>
    /// A dictation that is entirely a command — or several, one after another ("close the tab and switch to
    /// Chrome") — is carried out, not typed. Returns false for ordinary speech.
    /// </summary>
    private async Task<bool> RunCommandsAsync(string heard)
    {
        VoiceCommand? Parse(string s) => VoiceCommands.Parse(s, AppLauncher.IsApp);
        var steps = CommandChain.Parts(heard, s => Parse(s) is not null);
        if (steps is null)
        {
            if (Parse(heard) is not { } single) return false;
            pill.ShowMessage(await CommandRunner.RunAsync(single));
            return true;
        }
        for (var i = 0; i < steps.Count; i++)
        {
            var command = Parse(steps[i])!;
            pill.ShowWorking($"{i + 1}/{steps.Count} · {steps[i]}");
            await CommandRunner.RunAsync(command);
            // Give an app that was just opened or switched to time to take the keyboard before the next step.
            if (i < steps.Count - 1) await Task.Delay(command is VoiceCommand.OpenApp or VoiceCommand.OpenUrl ? 900 : 300);
        }
        pill.ShowMessage(CommandChain.Summary(steps), 3);
        return true;
    }

    private async Task TypeAsync(string heard)
    {
        var text = EvooPipeline.Process(heard);
        if (text.Length == 0) { pill.ShowMessage("Didn't catch that"); return; }
        if (PolishOn && RefinePrompt.NeedsPolish(text))
        {
            pill.ShowWorking("Polishing…");
            text = (await polisher.PolishAsync(text)).Text;
        }
        pill.HidePill();
        // Typing into Evoo's own try-it box needs no clipboard round trip.
        if (window.IsActive && window.TryBox.IsKeyboardFocused) window.TryBox.SelectedText = text + " ";
        else await Paster.PasteAsync(text + " ");
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
        polisher.Dispose();
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

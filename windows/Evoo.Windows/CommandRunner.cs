using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading.Tasks;
using Evoo.Core;
using NAudio.CoreAudioApi;

namespace Evoo.Windows;

/// <summary>Carries out a spoken command on Windows and says, in a few words, what it did.</summary>
internal static class CommandRunner
{
    private static readonly Dictionary<string, int> VirtualKeys = new()
    {
        ["enter"] = 0x0D, ["escape"] = 0x1B, ["tab"] = 0x09, ["space"] = 0x20, ["backspace"] = 0x08, ["delete"] = 0x2E,
        ["left"] = 0x25, ["up"] = 0x26, ["right"] = 0x27, ["down"] = 0x28, ["home"] = 0x24, ["end"] = 0x23,
        ["pageup"] = 0x21, ["pagedown"] = 0x22, ["="] = 0xBB, ["-"] = 0xBD,
    };

    private static int? VirtualKey(string key)
    {
        if (VirtualKeys.TryGetValue(key, out var vk)) return vk;
        if (key.Length == 1 && char.IsLetterOrDigit(key[0])) return char.ToUpperInvariant(key[0]);
        if (key.Length is 2 or 3 && key[0] == 'f' && int.TryParse(key[1..], out var n) && n is >= 1 and <= 12) return 0x6F + n;
        return null;
    }

    /// <summary>The keys the person held to talk must be up first, or Ctrl+T would arrive as Ctrl+Win+Shift+T.</summary>
    public static async Task WaitForKeysUpAsync()
    {
        for (var i = 0; i < 40 && (Native.IsDown(Native.VK_LWIN) || Native.IsDown(Native.VK_RWIN) || Native.IsDown(Native.VK_CONTROL) ||
                                   Native.IsDown(Native.VK_SHIFT) || Native.IsDown(Native.VK_MENU)); i++)
            await Task.Delay(25);
    }

    private static bool Press(KeyCombo combo)
    {
        if (VirtualKey(combo.Key) is not { } key) return false;
        var down = new List<Native.INPUT>();
        var up = new List<Native.INPUT>();
        void Modifier(bool on, int vk) { if (on) { down.Add(Native.Key(vk, false)); up.Insert(0, Native.Key(vk, true)); } }
        Modifier(combo.Ctrl, Native.VK_CONTROL);
        Modifier(combo.Shift, Native.VK_SHIFT);
        Modifier(combo.Alt, Native.VK_MENU);
        Modifier(combo.Win, Native.VK_LWIN);
        down.Add(Native.Key(key, false));
        down.Add(Native.Key(key, true));
        down.AddRange(up);
        Native.Send(down.ToArray());
        return true;
    }

    private static void Tap(int vk, int times = 1)
    {
        for (var i = 0; i < times; i++) Native.Send(Native.Key(vk, false), Native.Key(vk, true));
    }

    public static async Task<string> RunAsync(VoiceCommand command)
    {
        await WaitForKeysUpAsync();
        try
        {
            switch (command)
            {
                case VoiceCommand.Keys k:
                    return Press(k.Combo) ? Capitalize(k.Name) : "Unknown key";
                case VoiceCommand.Volume v:
                    using (var device = new MMDeviceEnumerator().GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia))
                    {
                        device.AudioEndpointVolume.Mute = false;
                        device.AudioEndpointVolume.MasterVolumeLevelScalar = v.Percent / 100f;
                    }
                    return $"Volume {v.Percent}%";
                case VoiceCommand.VolumeStep s:
                    Tap(s.Up ? 0xAF : 0xAE, 3); // the volume keys, three notches
                    return s.Up ? "Volume up" : "Volume down";
                case VoiceCommand.Mute m:
                    using (var device = new MMDeviceEnumerator().GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia))
                        device.AudioEndpointVolume.Mute = m.On;
                    return m.On ? "Muted" : "Unmuted";
                case VoiceCommand.Media media:
                    Tap(media.Key switch { MediaKey.Next => 0xB0, MediaKey.Previous => 0xB1, _ => 0xB3 });
                    return media.Key switch { MediaKey.Next => "Next", MediaKey.Previous => "Previous", _ => "Play/Pause" };
                case VoiceCommand.Window w:
                    Press(new KeyCombo(w.Action switch { WindowAction.Maximize => "up", WindowAction.Minimize => "down", WindowAction.Left => "left", _ => "right" }, Win: true));
                    return w.Action switch { WindowAction.Maximize => "Maximized", WindowAction.Minimize => "Minimized", WindowAction.Left => "Snapped left", _ => "Snapped right" };
                case VoiceCommand.OpenUrl url:
                    Process.Start(new ProcessStartInfo(url.Url) { UseShellExecute = true });
                    return "Opened " + url.Label;
                case VoiceCommand.OpenApp app:
                    return AppLauncher.Open(app.Name) ? Capitalize(app.Name) : $"Couldn't open “{app.Name}”";
            }
        }
        catch (Exception e)
        {
            return "Couldn't do that: " + e.Message;
        }
        return "Unknown command";
    }

    private static string Capitalize(string s) => s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s[1..];
}

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;

namespace Evoo.Windows;

/// <summary>
/// "Open Chrome", "switch to Notepad": finds apps the way the Start menu does (its shortcuts), plus the handful of
/// Windows tools that have no shortcut. If the app is already running it is brought forward, not started again.
/// </summary>
internal static class AppLauncher
{
    private static readonly Dictionary<string, string> BuiltIn = new()
    {
        ["notepad"] = "notepad.exe", ["calculator"] = "calc.exe", ["paint"] = "mspaint.exe",
        ["fileexplorer"] = "explorer.exe", ["explorer"] = "explorer.exe", ["files"] = "explorer.exe",
        ["settings"] = "ms-settings:", ["terminal"] = "wt.exe", ["taskmanager"] = "taskmgr.exe",
        ["commandprompt"] = "cmd.exe", ["snippingtool"] = "snippingtool.exe",
    };

    /// <summary>What people say → what the Start menu calls it.</summary>
    private static readonly Dictionary<string, string> Aliases = new()
    {
        ["chrome"] = "googlechrome", ["edge"] = "microsoftedge", ["vscode"] = "visualstudiocode", ["code"] = "visualstudiocode",
        ["word"] = "word", ["excel"] = "excel", ["powerpoint"] = "powerpoint", ["outlook"] = "outlook", ["teams"] = "microsoftteams",
    };

    private static Dictionary<string, string>? shortcuts;

    private static string Plain(string s) => new(s.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());

    private static Dictionary<string, string> Shortcuts()
    {
        if (shortcuts is not null) return shortcuts;
        var found = new Dictionary<string, string>();
        foreach (var folder in new[] { Environment.SpecialFolder.CommonPrograms, Environment.SpecialFolder.Programs })
        {
            try
            {
                var root = Environment.GetFolderPath(folder);
                if (!Directory.Exists(root)) continue;
                foreach (var file in Directory.EnumerateFiles(root, "*.lnk", SearchOption.AllDirectories))
                {
                    var name = Plain(Path.GetFileNameWithoutExtension(file));
                    if (name.Length > 0 && !name.Contains("uninstall")) found.TryAdd(name, file);
                }
            }
            catch { /* a folder we can't read: skip it */ }
        }
        return shortcuts = found;
    }

    /// <summary>The thing to start for a spoken app name, or null if this PC has no such app.</summary>
    public static string? Resolve(string spoken)
    {
        var p = Plain(spoken);
        if (p.Length < 2) return null;
        if (BuiltIn.TryGetValue(p, out var tool)) return tool;
        var all = Shortcuts();
        if (all.TryGetValue(p, out var exact)) return exact;
        if (Aliases.TryGetValue(p, out var alias) && all.TryGetValue(alias, out var aliased)) return aliased;
        if (p.Length < 4) return null;
        // "chrome" → "Google Chrome", "visual studio" → "Visual Studio 2022"
        var close = all.Keys.Where(k => k.EndsWith(p) || k.StartsWith(p)).OrderBy(k => k.Length).FirstOrDefault();
        return close is null ? null : all[close];
    }

    public static bool IsApp(string spoken) => Resolve(spoken) is not null;

    /// <summary>Brings the app forward if it's running, otherwise starts it. Returns false if it couldn't.</summary>
    public static bool Open(string spoken)
    {
        var target = Resolve(spoken);
        if (target is null) return false;
        var p = Plain(spoken);
        try
        {
            foreach (var process in Process.GetProcesses())
            {
                using (process)
                {
                    if (process.MainWindowHandle == IntPtr.Zero) continue;
                    var name = Plain(process.ProcessName);
                    if (name != p && !(p.Length >= 4 && Plain(process.MainWindowTitle).EndsWith(p)) &&
                        !(Aliases.TryGetValue(p, out var alias) && alias.EndsWith(name) && name.Length >= 4)) continue;
                    BringForward(process.MainWindowHandle);
                    return true;
                }
            }
        }
        catch { /* fall through to starting it */ }
        try
        {
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
            return true;
        }
        catch { return false; }
    }

    private static void BringForward(IntPtr window)
    {
        if (Native.IsIconic(window)) Native.ShowWindow(window, Native.SW_RESTORE);
        // Windows only lets the app that last received input move another window forward; a tap of Alt counts.
        Native.Send(Native.Key(Native.VK_MENU, false), Native.Key(Native.VK_MENU, true));
        Native.SetForegroundWindow(window);
    }
}

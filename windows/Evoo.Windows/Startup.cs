using System;
using Microsoft.Win32;

namespace Evoo.Windows;

/// <summary>"Start Evoo when I sign in": one value under the current user's Run key. No admin rights needed.</summary>
internal static class Startup
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue("Evoo") is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value) key.SetValue("Evoo", "\"" + Environment.ProcessPath + "\" --background");
            else key.DeleteValue("Evoo", false);
        }
    }
}
